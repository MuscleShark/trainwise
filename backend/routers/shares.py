"""Sharing a template with a link (ironsage.app/p/<code>) that anyone can copy from.

The owner shares one of their own templates and gets a code. The link shows a snapshot
of the template taken then, read without signing in (the web page, and the app before
copying). A signed-in user copies it into their own templates; custom exercises it uses
come along as the copier's own (or theirs of the same name, when they have one).
"""

import secrets
import string
import uuid

from fastapi import APIRouter, Depends, HTTPException, Response, status
from sqlalchemy import func, select
from sqlalchemy.orm import Session

from database import get_db
from models import Exercise, Template, TemplateShare, User, utcnow
from routers.templates import WITH_DAYS, visible_template
from schemas import (
    SharedExercise,
    SharedTemplate,
    TemplateDayWrite,
    TemplateExerciseWrite,
    TemplateRead,
    TemplateShareRead,
    TemplateWrite,
)
from security import get_current_user
from sync import commit_or_conflict, next_change_seq, not_found, template_days, template_read

router = APIRouter(tags=["Sharing"])

CODE_ALPHABET = string.ascii_letters + string.digits
# 62^10 ≈ 8 × 10^17: a code can't be guessed.
CODE_LENGTH = 10


def new_code() -> str:
    return "".join(secrets.choice(CODE_ALPHABET) for _ in range(CODE_LENGTH))


def own_custom_template(db: Session, user: User, template_id: uuid.UUID) -> Template:
    template = db.get(Template, template_id, options=[WITH_DAYS])
    if template is None or template.deleted_at is not None or template.owner_user_id != user.id:
        # Built-in templates are everyone's already: there is nothing to share.
        raise not_found("Template")
    return template


def share_read(share: TemplateShare) -> TemplateShareRead:
    return TemplateShareRead(
        code=share.code,
        template_id=share.template_id,
        shared_at=share.shared_at,
        copy_count=share.copy_count,
    )


def snapshot(db: Session, template: Template) -> dict:
    """The template as it is now, with the exercises it uses, as JSON."""
    read = template_read(template)
    exercise_ids = {e.exercise_id for day in read.days for e in day.exercises}
    exercises = db.scalars(select(Exercise).where(Exercise.id.in_(exercise_ids)))
    shared = [
        SharedExercise.model_validate(
            {
                **{
                    field: getattr(exercise, field)
                    for field in SharedExercise.model_fields
                    if field != "is_custom"
                },
                "is_custom": exercise.owner_user_id is not None,
            }
        )
        for exercise in sorted(exercises, key=lambda e: e.name_en)
    ]
    return {
        **read.model_dump(
            mode="json",
            include={"name_en", "name_zh", "level", "days_per_week", "notes", "days"},
        ),
        "exercises": [exercise.model_dump(mode="json") for exercise in shared],
    }


def live_share(db: Session, code: str) -> TemplateShare:
    """A share that still works: not stopped, and its template not deleted."""
    share = db.get(TemplateShare, code)
    if share is None or share.revoked_at is not None:
        raise not_found("Shared template")
    template = db.get(Template, share.template_id)
    if template is None or template.deleted_at is not None:
        raise not_found("Shared template")
    return share


def shared_template(share: TemplateShare) -> SharedTemplate:
    return SharedTemplate.model_validate(
        {**share.snapshot, "code": share.code, "shared_at": share.shared_at}
    )


@router.put("/templates/{template_id}/share", response_model=TemplateShareRead)
def share_template(
    template_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Shares one of the user's templates, or takes a new snapshot of it when it is
    shared already. The code stays the same, so links already sent keep working."""
    template = own_custom_template(db, current_user, template_id)
    share = db.scalar(select(TemplateShare).where(TemplateShare.template_id == template.id))
    now = utcnow()
    if share is None:
        share = TemplateShare(
            code=new_code(),
            template_id=template.id,
            owner_user_id=current_user.id,
            created_at=now,
        )
        db.add(share)
    share.snapshot = snapshot(db, template)
    share.shared_at = now
    share.revoked_at = None
    db.commit()
    return share_read(share)


@router.get("/templates/{template_id}/share", response_model=TemplateShareRead)
def get_template_share(
    template_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """The template's share link, while it is shared."""
    template = own_custom_template(db, current_user, template_id)
    share = db.scalar(select(TemplateShare).where(TemplateShare.template_id == template.id))
    if share is None or share.revoked_at is not None:
        raise not_found("Share")
    return share_read(share)


@router.delete("/templates/{template_id}/share", status_code=status.HTTP_204_NO_CONTENT)
def stop_sharing_template(
    template_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Stops sharing: the link no longer opens. Copies already made are kept."""
    template = own_custom_template(db, current_user, template_id)
    share = db.scalar(select(TemplateShare).where(TemplateShare.template_id == template.id))
    if share is not None and share.revoked_at is None:
        share.revoked_at = utcnow()
        db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/shared-templates/{code}", response_model=SharedTemplate)
def get_shared_template(code: str, db: Session = Depends(get_db)):
    """A shared template, for anyone with the link: no sign-in, nothing about who
    shared it."""
    return shared_template(live_share(db, code))


@router.post(
    "/shared-templates/{code}/copy",
    response_model=TemplateRead,
    status_code=status.HTTP_201_CREATED,
)
def copy_shared_template(
    code: str,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Copies a shared template into the user's own templates, with new ids. Built-in
    exercises are used as they are; each custom one becomes the user's own: theirs of
    the same name when they have one, otherwise a new copy. The next sync brings both
    to the user's devices."""
    share = live_share(db, code)
    shared = shared_template(share)

    exercise_ids: dict[uuid.UUID, uuid.UUID] = {}
    for exercise in shared.exercises:
        exercise_ids[exercise.id] = usable_exercise(db, current_user, exercise)

    template_data = TemplateWrite(
        name_en=shared.name_en,
        name_zh=shared.name_zh,
        level=shared.level,
        days_per_week=shared.days_per_week,
        notes=shared.notes,
        days=[
            TemplateDayWrite(
                id=uuid.uuid4(),
                name=day.name,
                name_zh=day.name_zh,
                exercises=[
                    TemplateExerciseWrite(
                        id=uuid.uuid4(),
                        exercise_id=exercise_ids[item.exercise_id],
                        rest_seconds=item.rest_seconds,
                        superset_group=item.superset_group,
                        sets=[s.model_copy(update={"id": uuid.uuid4()}) for s in item.sets],
                    )
                    for item in day.exercises
                ],
            )
            for day in shared.days
        ],
    )
    template = Template(id=uuid.uuid4(), owner_user_id=current_user.id)
    for field, value in template_data.model_dump(exclude={"days"}).items():
        setattr(template, field, value)
    template.days = template_days(template_data)
    template.change_seq = next_change_seq(db, current_user)
    db.add(template)
    share.copy_count += 1
    commit_or_conflict(db)
    return template_read(visible_template(db, current_user, template.id))


def usable_exercise(db: Session, user: User, exercise: SharedExercise) -> uuid.UUID:
    """The id of an exercise the user may use in place of a shared one."""
    found = db.get(Exercise, exercise.id)
    if found is not None and found.deleted_at is None and found.owner_user_id in (None, user.id):
        return found.id
    if not exercise.is_custom:
        # A built-in exercise that has since left the catalog.
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, f"Unknown exercise: {exercise.id}"
        )
    same_name = db.scalar(
        select(Exercise.id).where(
            Exercise.owner_user_id == user.id,
            Exercise.deleted_at.is_(None),
            Exercise.kind == exercise.kind,
            func.lower(Exercise.name_en) == exercise.name_en.lower(),
        )
    )
    if same_name is not None:
        return same_name
    base = db.get(Exercise, exercise.base_exercise_id) if exercise.base_exercise_id else None
    copy = Exercise(
        id=uuid.uuid4(),
        owner_user_id=user.id,
        name_en=exercise.name_en,
        name_zh=exercise.name_zh,
        equipment=exercise.equipment,
        load_type=exercise.load_type,
        primary_muscles=exercise.primary_muscles,
        secondary_muscles=exercise.secondary_muscles,
        aliases=[],
        base_exercise_id=base.id if base is not None and base.owner_user_id is None else None,
        kind=exercise.kind,
        cardio_metrics=exercise.cardio_metrics,
        change_seq=next_change_seq(db, user),
    )
    db.add(copy)
    db.flush()
    return copy.id
