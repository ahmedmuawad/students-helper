"""اختبارات مزامنة بيانات الطالب.

بتشتغل على SQLite افتراضيًا، وعلى MySQL كمان لو TEST_MYSQL_URL متظبط —
عشان نتأكد إن القفل والعدّاد شغّالين على قاعدة البيانات الحقيقية.
"""

from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone

import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

import app.models  # noqa: F401  — لازم يتسجّل قبل create_all
from app.core.database import Base, get_db
from app.core.schema_sync import sync_schema

DATABASE_URLS = ["sqlite"]
if os.environ.get("TEST_MYSQL_URL"):
    DATABASE_URLS.append("mysql")


@pytest.fixture(params=DATABASE_URLS)
def client(request, tmp_path, monkeypatch):
    monkeypatch.setenv("ALLOW_DEV_TOKENS", "1")

    if request.param == "mysql":
        url = os.environ["TEST_MYSQL_URL"]
        engine = create_engine(url, future=True)
        Base.metadata.drop_all(bind=engine)
    else:
        engine = create_engine(f"sqlite:///{tmp_path / 'sync.db'}", future=True)

    Base.metadata.create_all(bind=engine)
    sync_schema(engine)
    Session = sessionmaker(bind=engine, autoflush=False, expire_on_commit=False)

    from app.core import security
    from app.main import app

    monkeypatch.setattr(security.settings, "allow_dev_tokens", True)

    def override_db():
        db = Session()
        try:
            yield db
        finally:
            db.close()

    app.dependency_overrides[get_db] = override_db
    with TestClient(app) as test_client:
        yield test_client
    app.dependency_overrides.clear()
    engine.dispose()


def auth(uid: str) -> dict[str, str]:
    return {"Authorization": f"Bearer dev:{uid}"}


NOW = datetime(2026, 9, 8, 10, 0, tzinfo=timezone.utc)


def record(kind: str, rid: str, payload: dict, at: datetime = NOW, deleted: bool = False):
    return {
        "kind": kind,
        "id": rid,
        "payload": payload,
        "updated_at": at.isoformat(),
        "deleted": deleted,
    }


# --------------------------------------------------------------------------


def test_a_new_account_syncs_empty(client):
    response = client.get("/api/v1/sync", headers=auth("ahmed"))
    assert response.status_code == 200
    body = response.json()
    assert body["records"] == []
    assert body["revision"] == 0
    assert body["has_more"] is False


def test_pushed_records_come_back_on_another_device(client):
    push = client.post(
        "/api/v1/sync",
        headers=auth("ahmed"),
        json={"since": 0, "records": [
            record("task", "t1", {"title": "واجب الرياضيات", "isDone": False}),
            record("period", "p1", {"weekday": 6, "periodNumber": 1}),
        ]},
    )
    assert push.status_code == 200, push.text
    assert push.json()["revision"] == 2

    # الجهاز التاني بيبدأ من الصفر فبيشوف الاتنين
    other = client.get("/api/v1/sync?since=0", headers=auth("ahmed")).json()
    assert {r["id"] for r in other["records"]} == {"t1", "p1"}
    titles = {r["id"]: r["payload"] for r in other["records"]}
    assert titles["t1"]["title"] == "واجب الرياضيات"


def test_sync_is_incremental(client):
    client.post("/api/v1/sync", headers=auth("ahmed"),
                json={"since": 0, "records": [record("task", "t1", {"title": "أ"})]})
    first = client.get("/api/v1/sync?since=0", headers=auth("ahmed")).json()

    client.post("/api/v1/sync", headers=auth("ahmed"),
                json={"since": first["revision"],
                      "records": [record("task", "t2", {"title": "ب"})]})

    # من الرقم الأول، مفروض نشوف الجديد بس
    later = client.get(
        f"/api/v1/sync?since={first['revision']}", headers=auth("ahmed")
    ).json()
    assert [r["id"] for r in later["records"]] == ["t2"]


def test_accounts_never_see_each_other(client):
    client.post("/api/v1/sync", headers=auth("ahmed"),
                json={"since": 0, "records": [record("task", "t1", {"title": "سري"})]})
    other = client.get("/api/v1/sync?since=0", headers=auth("mona")).json()
    assert other["records"] == []


def test_the_newer_edit_wins(client):
    client.post("/api/v1/sync", headers=auth("ahmed"), json={
        "since": 0,
        "records": [record("task", "t1", {"title": "قديم"}, at=NOW)],
    })
    # جهاز تاني بيبعت تعديل أحدث
    client.post("/api/v1/sync", headers=auth("ahmed"), json={
        "since": 0,
        "records": [record("task", "t1", {"title": "جديد"},
                           at=NOW + timedelta(minutes=5))],
    })
    body = client.get("/api/v1/sync?since=0", headers=auth("ahmed")).json()
    assert len(body["records"]) == 1
    assert body["records"][0]["payload"]["title"] == "جديد"


def test_a_stale_edit_is_rejected_and_corrected(client):
    client.post("/api/v1/sync", headers=auth("ahmed"), json={
        "since": 0,
        "records": [record("task", "t1", {"title": "الأحدث"},
                           at=NOW + timedelta(minutes=10))],
    })
    # جهاز كان أوفلاين بيبعت نسخة أقدم
    response = client.post("/api/v1/sync", headers=auth("ahmed"), json={
        "since": 0,
        "records": [record("task", "t1", {"title": "قديم"}, at=NOW)],
    }).json()

    assert response["rejected"] == ["task:t1"]
    # والرد بيحمل نسخة السيرفر عشان الجهاز يصحّح نفسه فورًا
    served = {r["id"]: r["payload"] for r in response["records"]}
    assert served["t1"]["title"] == "الأحدث"


def test_the_same_timestamp_lets_the_write_through(client):
    """تعديل بنفس التوقيت مش تعارض — بنقبله عشان إعادة الإرسال تنجح."""
    for title in ("أول", "تاني"):
        client.post("/api/v1/sync", headers=auth("ahmed"), json={
            "since": 0, "records": [record("task", "t1", {"title": title})],
        })
    body = client.get("/api/v1/sync?since=0", headers=auth("ahmed")).json()
    assert body["records"][0]["payload"]["title"] == "تاني"


def test_deletes_travel_to_the_other_device(client):
    client.post("/api/v1/sync", headers=auth("ahmed"),
                json={"since": 0, "records": [record("task", "t1", {"title": "أ"})]})
    client.post("/api/v1/sync", headers=auth("ahmed"), json={
        "since": 0,
        "records": [record("task", "t1", {}, at=NOW + timedelta(minutes=1),
                           deleted=True)],
    })
    body = client.get("/api/v1/sync?since=0", headers=auth("ahmed")).json()
    assert len(body["records"]) == 1
    assert body["records"][0]["deleted"] is True


def test_every_record_kind_is_accepted(client):
    kinds = ["profile", "subject", "period", "lesson", "instructor", "task"]
    response = client.post("/api/v1/sync", headers=auth("ahmed"), json={
        "since": 0,
        "records": [record(kind, f"{kind}-1", {"n": i})
                    for i, kind in enumerate(kinds)],
    })
    assert response.status_code == 200, response.text
    body = client.get("/api/v1/sync?since=0", headers=auth("ahmed")).json()
    assert {r["kind"] for r in body["records"]} == set(kinds)


def test_an_unknown_kind_is_refused(client):
    response = client.post("/api/v1/sync", headers=auth("ahmed"), json={
        "since": 0, "records": [record("secrets", "x", {})],
    })
    assert response.status_code == 422


def test_an_oversized_record_is_refused(client):
    huge = {"blob": "ا" * 70_000}
    response = client.post("/api/v1/sync", headers=auth("ahmed"), json={
        "since": 0, "records": [record("task", "t1", huge)],
    })
    assert response.status_code == 422


def test_sync_needs_a_token(client):
    assert client.get("/api/v1/sync").status_code == 401
    assert client.post("/api/v1/sync", json={"since": 0, "records": []}).status_code == 401


def test_arabic_survives_the_round_trip(client):
    payload = {"title": "مراجعة الوحدة الأولى", "note": "صفحة ٤٥ — مهم"}
    client.post("/api/v1/sync", headers=auth("ahmed"),
                json={"since": 0, "records": [record("task", "t1", payload)]})
    body = client.get("/api/v1/sync?since=0", headers=auth("ahmed")).json()
    assert body["records"][0]["payload"] == payload


def test_wiping_removes_everything(client):
    client.post("/api/v1/sync", headers=auth("ahmed"),
                json={"since": 0, "records": [record("task", "t1", {"title": "أ"})]})
    assert client.delete("/api/v1/sync", headers=auth("ahmed")).status_code == 200
    body = client.get("/api/v1/sync?since=0", headers=auth("ahmed")).json()
    assert body["records"] == []


def test_the_revision_never_goes_backwards(client):
    seen = 0
    for index in range(5):
        body = client.post("/api/v1/sync", headers=auth("ahmed"), json={
            "since": seen,
            "records": [record("task", f"t{index}", {"n": index})],
        }).json()
        assert body["revision"] > seen
        seen = body["revision"]


# --------------------------------------------------------------------------
# ولي الأمر
# --------------------------------------------------------------------------


def link_guardian(client, permissions: dict) -> int:
    """يربط ولي أمر بالطالب ويرجّع رقم الطالب."""
    code = client.post("/api/v1/link-codes", headers=auth("ahmed")).json()["code"]
    link = client.post(
        "/api/v1/links/redeem",
        headers=auth("baba"),
        json={"code": code, "relation": "father"},
    )
    assert link.status_code in (200, 201), link.text
    link_id = link.json()["id"]
    # الطالب بيوافق ويحدّد الصلاحيات
    response = client.post(
        f"/api/v1/links/{link_id}/respond",
        headers=auth("ahmed"),
        json={"accept": True, "permissions": permissions},
    )
    assert response.status_code == 200, response.text
    return client.get("/api/v1/children", headers=auth("baba")).json()[0]["student_id"]


ALL_ALLOWED = {
    "viewTimetable": True, "viewLessons": True, "viewTasks": True,
    "viewLessonCosts": True,
}


def seed_child_data(client):
    client.post("/api/v1/sync", headers=auth("ahmed"), json={"since": 0, "records": [
        record("task", "t1", {"title": "واجب", "isDone": False}),
        record("period", "p1", {"weekday": 6, "subjectId": "math"}),
        record("lesson", "l1", {"teacherName": "أ. سامي", "cost": 250.0}),
        record("profile", "me", {"name": "أحمد", "birthDate": "2010-05-01"}),
    ]})


def test_a_guardian_with_no_children_sees_none(client):
    assert client.get("/api/v1/children", headers=auth("baba")).json() == []


def test_a_guardian_reads_the_child_data(client):
    seed_child_data(client)
    student_id = link_guardian(client, ALL_ALLOWED)

    body = client.get(
        f"/api/v1/children/{student_id}/records", headers=auth("baba")
    ).json()
    kinds = {r["kind"] for r in body["records"]}
    assert kinds == {"task", "period", "lesson"}


def test_the_profile_is_never_shared(client):
    """الملف الشخصي بيانات خاصة — مفيش صلاحية بتفتحه أصلاً."""
    seed_child_data(client)
    student_id = link_guardian(client, {**ALL_ALLOWED, "viewProfile": True})
    body = client.get(
        f"/api/v1/children/{student_id}/records", headers=auth("baba")
    ).json()
    assert all(r["kind"] != "profile" for r in body["records"])


def test_a_closed_permission_hides_its_records(client):
    seed_child_data(client)
    student_id = link_guardian(client, {**ALL_ALLOWED, "viewTasks": False})
    body = client.get(
        f"/api/v1/children/{student_id}/records", headers=auth("baba")
    ).json()
    assert all(r["kind"] != "task" for r in body["records"])
    assert any(r["kind"] == "period" for r in body["records"])


def test_costs_are_stripped_not_just_hidden(client):
    """لو الطالب مقفل المصاريف، السيرفر بيشيلها من الرد نفسه."""
    seed_child_data(client)
    student_id = link_guardian(client, {**ALL_ALLOWED, "viewLessonCosts": False})
    body = client.get(
        f"/api/v1/children/{student_id}/records", headers=auth("baba")
    ).json()
    lesson = next(r for r in body["records"] if r["kind"] == "lesson")
    assert "cost" not in lesson["payload"]
    assert lesson["payload"]["teacherName"] == "أ. سامي"


def test_a_stranger_cannot_read_a_child(client):
    seed_child_data(client)
    student_id = link_guardian(client, ALL_ALLOWED)
    response = client.get(
        f"/api/v1/children/{student_id}/records", headers=auth("stranger")
    )
    assert response.status_code == 404


def test_a_guardian_cannot_write_to_the_child(client):
    """المزامنة بتكتب في حساب المتصل نفسه — عمرها ما بتلمس حساب تاني."""
    seed_child_data(client)
    link_guardian(client, ALL_ALLOWED)
    client.post("/api/v1/sync", headers=auth("baba"), json={
        "since": 0, "records": [record("task", "t1", {"title": "من بابا"})],
    })
    child = client.get("/api/v1/sync?since=0", headers=auth("ahmed")).json()
    titles = {r["id"]: r["payload"].get("title") for r in child["records"]}
    assert titles["t1"] == "واجب"


def test_the_child_read_is_incremental_too(client):
    seed_child_data(client)
    student_id = link_guardian(client, ALL_ALLOWED)
    first = client.get(
        f"/api/v1/children/{student_id}/records", headers=auth("baba")
    ).json()

    client.post("/api/v1/sync", headers=auth("ahmed"), json={
        "since": 0,
        "records": [record("task", "t2", {"title": "جديد"},
                           at=NOW + timedelta(hours=1))],
    })
    later = client.get(
        f"/api/v1/children/{student_id}/records?since={first['revision']}",
        headers=auth("baba"),
    ).json()
    assert [r["id"] for r in later["records"]] == ["t2"]
