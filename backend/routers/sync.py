from typing import Annotated

from fastapi import APIRouter, Depends, Query
from sqlalchemy import select, union_all
from sqlalchemy.orm import Session

from database import get_db
from models import (
    BodyMeasurement,
    DailyReadiness,
    Exercise,
    Profile,
    Recommendation,
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
    limit: Annotated[int, Query(ge=1, le=500)] = 200,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Returns up to `limit` of the user's records changed after `since`, deletions included.

    Store the returned `change_seq` and send it as `since` next time. While `has_more`
    is true, call again right away. `since=0` starts from the beginning. The built-in
    catalog comes from GET /v1/exercises and GET /v1/templates instead.

    Every change takes a unique value of the user's counter, so a page ends exactly at
    the `limit`-th change and the next page starts after it.
    """
    owned = [
        (Profile, Profile.user_id),
        (Exercise, Exercise.owner_user_id),
        (Workout, Workout.user_id),
        (Template, Template.owner_user_id),
        (BodyMeasurement, BodyMeasurement.user_id),
        (DailyReadiness, DailyReadiness.user_id),
        (Recommendation, Recommendation.user_id),
    ]
    changes = union_all(
        *(
            select(model.change_seq.label("seq")).where(
                owner == current_user.id, model.change_seq > since
            )
            for model, owner in owned
        )
    ).subquery()
    page = list(db.scalars(select(changes.c.seq).order_by(changes.c.seq).limit(limit + 1)))
    has_more = len(page) > limit
    upto = page[min(len(page), limit) - 1] if page else since

    def changed(model, owner, *options):
        return db.scalars(
            select(model)
            .options(*options)
            .where(owner == current_user.id, model.change_seq > since, model.change_seq <= upto)
            .order_by(model.change_seq)
        )

    profile = db.get(Profile, current_user.id)
    return SyncResponse(
        change_seq=upto,
        has_more=has_more,
        profile=profile if profile is not None and since < profile.change_seq <= upto else None,
        exercises=[exercise_read(e) for e in changed(Exercise, Exercise.owner_user_id)],
        workouts=list(changed(Workout, Workout.user_id, WITH_SETS)),
        templates=[template_read(t) for t in changed(Template, Template.owner_user_id, WITH_DAYS)],
        body_measurements=list(changed(BodyMeasurement, BodyMeasurement.user_id)),
        readiness=list(changed(DailyReadiness, DailyReadiness.user_id)),
        recommendations=list(changed(Recommendation, Recommendation.user_id)),
    )
