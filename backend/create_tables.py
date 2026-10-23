import models  # noqa: F401  (registers the tables on Base.metadata)
from database import Base, engine

Base.metadata.create_all(bind=engine)

print("Tables created successfully!")