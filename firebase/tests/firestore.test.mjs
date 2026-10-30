// firebase/firestore.rules 테스트
import { after, before, beforeEach, describe, test } from "node:test";
import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import {
    collection, deleteDoc, doc, getDoc, getDocs, serverTimestamp, setDoc, updateDoc, writeBatch,
} from "firebase/firestore";
import {
    INSTRUCTOR, MEMBER, MEMBER_ID, PIN, RECORDING_ID, SESSION_ID, STRANGER,
    createEnvironment, seed, sessionData,
} from "./support.mjs";

let env;
before(async () => { env = await createEnvironment(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => { await env.clearFirestore(); });

const db = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).firestore();

/// 교관 앱처럼 세션과 PIN을 한 번에 만든다.
function createSession(uid, session, pin = PIN) {
    const firestore = db(uid);
    const batch = writeBatch(firestore);
    batch.set(doc(firestore, "sessions", SESSION_ID), session);
    batch.set(doc(firestore, "pins", pin), { sessionID: SESSION_ID });
    return batch.commit();
}

describe("세션 만들기", () => {
    test("교관은 세션과 PIN을 함께 만든다", async () => {
        await assertSucceeds(createSession(INSTRUCTOR, sessionData()));
    });

    test("PIN 없이 세션만 만들 수 없다", async () => {
        await assertFails(setDoc(doc(db(INSTRUCTOR), "sessions", SESSION_ID), sessionData()));
    });

    test("다른 사람을 교관으로 적을 수 없다", async () => {
        await assertFails(createSession(STRANGER, sessionData()));
    });

    test("시작한 상태나 시작 시각을 넣어 만들 수 없다", async () => {
        await assertFails(createSession(INSTRUCTOR, sessionData({ status: "running" })));
        await assertFails(createSession(INSTRUCTOR, sessionData({ startedAt: serverTimestamp() })));
    });

    test("로그인하지 않으면 만들 수 없다", async () => {
        await assertFails(createSession(null, sessionData()));
    });
});

describe("세션 상태 바꾸기", () => {
    beforeEach(async () => { await seed(env); });

    test("교관은 훈련을 시작하며 서버 시각을 기록한다", async () => {
        await assertSucceeds(updateDoc(doc(db(INSTRUCTOR), "sessions", SESSION_ID), {
            status: "running", startedAt: serverTimestamp(),
        }));
    });

    test("상태를 되돌릴 수 없다", async () => {
        await assertFails(updateDoc(doc(db(INSTRUCTOR), "sessions", SESSION_ID), { status: "preparing" }));
    });

    test("상태와 시작 시각 말고는 바꿀 수 없다", async () => {
        await assertFails(updateDoc(doc(db(INSTRUCTOR), "sessions", SESSION_ID), { status: "running", name: "바꾼 이름" }));
    });

    test("다른 사람은 세션을 바꿀 수 없다", async () => {
        await assertFails(updateDoc(doc(db(MEMBER), "sessions", SESSION_ID), { status: "ended" }));
    });

    test("로그인한 사용자는 세션을 읽는다", async () => {
        await assertSucceeds(getDoc(doc(db(MEMBER), "sessions", SESSION_ID)));
        await assertFails(getDoc(doc(db(null), "sessions", SESSION_ID)));
    });
});

describe("PIN", () => {
    beforeEach(async () => { await seed(env, { member: false, recording: false }); });

    test("로그인한 사용자는 PIN 하나를 읽지만 목록은 볼 수 없다", async () => {
        await assertSucceeds(getDoc(doc(db(MEMBER), "pins", PIN)));
        await assertFails(getDocs(collection(db(MEMBER), "pins")));
    });

    test("세션의 교관만 PIN을 지운다", async () => {
        await assertFails(deleteDoc(doc(db(MEMBER), "pins", PIN)));
        await assertSucceeds(deleteDoc(doc(db(INSTRUCTOR), "pins", PIN)));
    });
});

describe("대원 입장과 준비", () => {
    const memberDoc = (uid) => doc(db(uid), "sessions", SESSION_ID, "members", MEMBER_ID);
    const joinData = (overrides = {}) => ({
        id: MEMBER_ID, sessionID: SESSION_ID, name: "대원 1", isReady: false,
        lastActiveAt: serverTimestamp(), uid: MEMBER, pin: PIN, ...overrides,
    });

    test("PIN이 맞으면 훈련 시작 전에 입장한다", async () => {
        await seed(env, { member: false, recording: false });
        await assertSucceeds(setDoc(memberDoc(MEMBER), joinData()));
    });

    test("PIN이 틀리거나 훈련이 시작됐으면 입장할 수 없다", async () => {
        await seed(env, { member: false, recording: false });
        await assertFails(setDoc(memberDoc(MEMBER), joinData({ pin: "000000" })));

        await env.clearFirestore();
        await seed(env, { status: "running", member: false, recording: false });
        await assertFails(setDoc(memberDoc(MEMBER), joinData()));
    });

    test("다른 사람의 uid로 입장할 수 없다", async () => {
        await seed(env, { member: false, recording: false });
        await assertFails(setDoc(memberDoc(STRANGER), joinData()));
    });

    test("훈련 시작 전에는 같은 대원 ID로 다시 입장하며 이름을 바꿀 수 있다", async () => {
        await seed(env, { recording: false });
        await assertSucceeds(setDoc(memberDoc(MEMBER), joinData({ name: "다시 입장" })));
    });

    test("훈련이 시작되면 대원은 준비 상태와 활동 시각만 바꾼다", async () => {
        await seed(env, { status: "running", recording: false });
        await assertSucceeds(updateDoc(memberDoc(MEMBER), { isReady: true, lastActiveAt: serverTimestamp() }));
        await assertFails(updateDoc(memberDoc(MEMBER), { name: "바꾼 이름", lastActiveAt: serverTimestamp() }));
    });

    test("대원 문서는 본인과 교관만 읽고, 목록은 교관만 본다", async () => {
        await seed(env, { recording: false });
        await assertSucceeds(getDoc(memberDoc(MEMBER)));
        await assertSucceeds(getDoc(memberDoc(INSTRUCTOR)));
        await assertFails(getDoc(memberDoc(STRANGER)));
        await assertSucceeds(getDocs(collection(db(INSTRUCTOR), "sessions", SESSION_ID, "members")));
        await assertFails(getDocs(collection(db(MEMBER), "sessions", SESSION_ID, "members")));
    });
});

describe("기록", () => {
    const recordingDoc = (uid) => doc(db(uid), "sessions", SESSION_ID, "recordings", RECORDING_ID);
    const recordingData = {
        identity: { sessionID: SESSION_ID, memberID: MEMBER_ID, recordingID: RECORDING_ID },
        state: "recording",
    };

    beforeEach(async () => { await seed(env, { recording: false }); });

    test("기록 주인은 서버 시각으로 기록을 쓴다", async () => {
        await assertSucceeds(setDoc(recordingDoc(MEMBER), { ...recordingData, lastActiveAt: serverTimestamp() }));
    });

    test("다른 사람은 남의 기록을 쓸 수 없다", async () => {
        await assertFails(setDoc(recordingDoc(STRANGER), { ...recordingData, lastActiveAt: serverTimestamp() }));
    });

    test("교관만 기록을 읽는다", async () => {
        await setDoc(recordingDoc(MEMBER), { ...recordingData, lastActiveAt: serverTimestamp() });
        await assertSucceeds(getDoc(recordingDoc(INSTRUCTOR)));
        await assertFails(getDoc(recordingDoc(MEMBER)));
    });
});
