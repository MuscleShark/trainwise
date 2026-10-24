from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select
from sqlalchemy.orm import Session

from database import get_db
from models import (
    BodyMeasurement,
    DailyReadiness,
    Exercise,
    Profile,
    Template,
    User,
    Workout,
)
from routers.templates import WITH_DAYS
from routers.workouts import WITH_SETS
from schemas import SyncResponse
from security import get_current_user
from sync import exercise_read, template_read

router = APIRouter(tags=["Sync"])


@router.get("/sync", response_model=SyncResponse)
def sync(
    since: Annotated[int, Query(ge=0)] = 0,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Returns the user's records changed after `since`, deleted ones included.

    Store the returned `change_seq` and send it as `since` next time. `since=0`
    returns everything. The built-in catalog comes from GET /v1/exercises and
    GET /v1/templates instead.
    """
    seq = db.scalar(select(User.change_seq).where(User.id == current_user.id))

    def changed(model, owner_column):
        return db.scalars(
            select(model)
            .where(owner_column == current_user.id, model.change_seq > since)
            .order_by(model.change_seq)
        )

    profile = db.get(Profile, current_user.id)
    return SyncResponse(
        change_seq=seq,
        profile=profile if profile is not None and profile.change_seq > since else None,
        exercises=[exercise_read(e) for e in changed(Exercise, Exercise.owner_user_id)],
        workouts=list(
            db.scalars(
                select(Workout)
                .options(WITH_SETS)
                .where(Workout.user_id == current_user.id, Workout.change_seq > since)
                .order_by(Workout.change_seq)
            )
        ),
        templates=[
            template_read(t)
            for t in db.scalars(
                select(Template)
                .options(WITH_DAYS)
                .where(Template.owner_user_id == current_user.id, Template.change_seq > since)
                .order_by(Template.change_seq)
            )
        ],
        body_measurements=list(changed(BodyMeasurement, BodyMeasurement.user_id)),
        readiness=list(changed(DailyReadiness, DailyReadiness.user_id)),
    )
