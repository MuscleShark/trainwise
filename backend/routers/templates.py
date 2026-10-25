import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import or_, select
from sqlalchemy.orm import Session, selectinload

from database import get_db
from models import Template, TemplateDay, TemplateExercise, User, utcnow
from schemas import TemplateRead, TemplateWrite
from security import get_current_user
from sync import (
    check_exercises_visible,
    commit_or_conflict,
    id_conflict,
    next_change_seq,
    not_found,
    template_days,
    template_read,
)

router = APIRouter(
    prefix="/templates",
    tags=["Templates"],
)

WITH_DAYS = (
    selectinload(Template.days)
    .selectinload(TemplateDay.exercises)
    .selectinload(TemplateExercise.sets)
)


def visible_template(db: Session, user: User, template_id: uuid.UUID) -> Template:
    template = db.get(Template, template_id, options=[WITH_DAYS])
    if (
        template is None
        or template.deleted_at is not None
        or template.owner_user_id not in (None, user.id)
    ):
        raise not_found("Template")
    return template


@router.get("", response_model=list[TemplateRead])
def list_templates(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Built-in templates plus the user's own."""
    templates = db.scalars(
        select(Template)
        .options(WITH_DAYS)
        .where(
            Template.deleted_at.is_(None),
            or_(Template.owner_user_id.is_(None), Template.owner_user_id == current_user.id),
        )
        .order_by(Template.name_en)
    )
    return [template_read(template) for template in templates]


@router.get("/{template_id}", response_model=TemplateRead)
def get_template(
    template_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    return template_read(visible_template(db, current_user, template_id))


@router.put("/{template_id}", response_model=TemplateRead)
def put_template(
    template_id: uuid.UUID,
    template_data: TemplateWrite,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Creates or completely replaces one of the user's own templates."""
    template = db.get(Template, template_id, options=[WITH_DAYS])
    if template is not None and template.owner_user_id is None:
        raise HTTPException(status.HTTP_403_FORBIDDEN, "Built-in templates cannot be changed")
    if template is not None and template.owner_user_id != current_user.id:
        raise id_conflict()
    check_exercises_visible(
        db,
        current_user,
        {exercise.exercise_id for day in template_data.days for exercise in day.exercises},
    )

    if template is None:
        template = Template(id=template_id, owner_user_id=current_user.id)
        db.add(template)
    else:
        template.days.clear()
        db.flush()

    for field, value in template_data.model_dump(exclude={"days"}).items():
        setattr(template, field, value)
    template.days = template_days(template_data)
    template.deleted_at = None
    template.change_seq = next_change_seq(db, current_user)
    commit_or_conflict(db)
    return template_read(visible_template(db, current_user, template_id))


@router.delete("/{template_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_template(
    template_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    template = db.get(Template, template_id)
    if template is None or template.owner_user_id != current_user.id:
        raise not_found("Template")
    if template.deleted_at is None:
        template.deleted_at = utcnow()
        template.change_seq = next_change_seq(db, current_user)
        db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)
