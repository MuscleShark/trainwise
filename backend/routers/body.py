import uuid
from datetime import date
from typing import Annotated

from fastapi import APIRouter, Depends, Query, Response, status
from pydantic import AwareDatetime
from sqlalchemy import select
from sqlalchemy.orm import Session

from database import get_db
from models import BodyMeasurement, DailyReadiness, User, utcnow
from schemas import BodyMeasurementRead, BodyMeasurementWrite, ReadinessRead, ReadinessWrite
from security import get_current_user
from sync import id_conflict, next_change_seq, not_found

router = APIRouter(tags=["Body and readiness"])


@router.get("/body-measurements", response_model=list[BodyMeasurementRead])
def list_body_measurements(
    from_: Annotated[AwareDatetime | None, Query(alias="from")] = None,
    to: AwareDatetime | None = None,
    kind: str | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = (
        select(BodyMeasurement)
        .where(BodyMeasurement.user_id == current_user.id, BodyMeasurement.deleted_at.is_(None))
        .order_by(BodyMeasurement.measured_at)
    )
    if from_ is not None:
        query = query.where(BodyMeasurement.measured_at >= from_)
    if to is not None:
        query = query.where(BodyMeasurement.measured_at < to)
    if kind is not None:
        query = query.where(BodyMeasurement.kind == kind)
    return list(db.scalars(query))


@router.put("/body-measurements/{measurement_id}", response_model=BodyMeasurementRead)
def put_body_measurement(
    measurement_id: uuid.UUID,
    measurement_data: BodyMeasurementWrite,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    measurement = db.get(BodyMeasurement, measurement_id)
    if measurement is not None and measurement.user_id != current_user.id:
        raise id_conflict()
    if measurement is None:
        measurement = BodyMeasurement(id=measurement_id, user_id=current_user.id)
        db.add(measurement)
    for field, value in measurement_data.model_dump().items():
        setattr(measurement, field, value)
    measurement.deleted_at = None
    measurement.change_seq = next_change_seq(db, current_user)
    db.commit()
    db.refresh(measurement)
    return measurement


@router.delete("/body-measurements/{measurement_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_body_measurement(
    measurement_id: uuid.UUID,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    measurement = db.get(BodyMeasurement, measurement_id)
    if measurement is None or measurement.user_id != current_user.id:
        raise not_found("Measurement")
    if measurement.deleted_at is None:
        measurement.deleted_at = utcnow()
        measurement.change_seq = next_change_seq(db, current_user)
        db.commit()
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/readiness", response_model=list[ReadinessRead])
def list_readiness(
    from_: Annotated[date | None, Query(alias="from")] = None,
    to: date | None = None,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    query = (
        select(DailyReadiness)
        .where(DailyReadiness.user_id == current_user.id, DailyReadiness.deleted_at.is_(None))
        .order_by(DailyReadiness.date)
    )
    if from_ is not None:
        query = query.where(DailyReadiness.date >= from_)
    if to is not None:
        query = query.where(DailyReadiness.date < to)
    return list(db.scalars(query))


@router.put("/readiness/{day}", response_model=ReadinessRead)
def put_readiness(
    day: date,
    readiness_data: ReadinessWrite,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user),
):
    """Creates or replaces the summary for one local date."""
    readiness = db.scalar(
        select(DailyReadiness).where(
            DailyReadiness.user_id == current_user.id, DailyReadiness.date == day
        )
    )
    if readiness is None:
        readiness = DailyReadiness(user_id=current_user.id, date=day)
        db.add(readiness)
    for field, value in readiness_data.model_dump().items():
        setattr(readiness, field, value)
    readiness.deleted_at = None
    readiness.change_seq = next_change_seq(db, current_user)
    db.commit()
    db.refresh(readiness)
    return readiness
