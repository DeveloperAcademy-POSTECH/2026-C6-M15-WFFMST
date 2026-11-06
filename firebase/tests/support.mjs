// 규칙 테스트 공통 준비. 에뮬레이터 주소는 firebase emulators:exec가 환경 변수로 넘겨 준다.
import { readFileSync } from "node:fs";
import { initializeTestEnvironment } from "@firebase/rules-unit-testing";
import { doc, setDoc, Timestamp } from "firebase/firestore";

export const INSTRUCTOR = "instructor-uid";
export const MEMBER = "member-uid";
export const STRANGER = "stranger-uid";

export const SESSION_ID = "11111111-1111-1111-1111-111111111111";
export const MEMBER_ID = "22222222-2222-2222-2222-222222222222";
export const RECORDING_ID = "33333333-3333-3333-3333-333333333333";
export const PIN = "123456";

export const FLOOR_PLAN = { floorPlanID: "44444444-4444-4444-4444-444444444444", navigationSHA256: "nav-sha" };

function hostAndPort(variable) {
    const value = process.env[variable];
    if (!value) throw new Error(`${variable}가 없다. firebase emulators:exec 안에서 실행한다.`);
    const index = value.lastIndexOf(":");
    return { host: value.slice(0, index), port: Number(value.slice(index + 1)) };
}

export async function createEnvironment() {
    return initializeTestEnvironment({
        projectId: process.env.GCLOUD_PROJECT ?? "demo-cqb-rules",
        firestore: {
            ...hostAndPort("FIRESTORE_EMULATOR_HOST"),
            rules: readFileSync(new URL("../firestore.rules", import.meta.url), "utf8"),
        },
        storage: {
            ...hostAndPort("FIREBASE_STORAGE_EMULATOR_HOST"),
            rules: readFileSync(new URL("../storage.rules", import.meta.url), "utf8"),
        },
    });
}

/// 교관 앱이 만드는 세션 문서 (CQBFirebase FirestoreEncoding.session과 같은 모양)
export function sessionData(overrides = {}) {
    return {
        id: SESSION_ID,
        pin: PIN,
        name: "오후 훈련",
        status: "waiting",
        floorPlan: FLOOR_PLAN,
        instructorUid: INSTRUCTOR,
        ...overrides,
    };
}

/// 규칙을 끄고 세션·대원·기록을 미리 넣는다.
export async function seed(env, { status = "waiting", member = true, recording = true } = {}) {
    await env.withSecurityRulesDisabled(async (context) => {
        const db = context.firestore();
        await setDoc(doc(db, "sessions", SESSION_ID), sessionData({ status }));
        await setDoc(doc(db, "pins", PIN), { sessionID: SESSION_ID });
        if (member) {
            await setDoc(doc(db, "sessions", SESSION_ID, "members", MEMBER_ID), {
                id: MEMBER_ID,
                sessionID: SESSION_ID,
                name: "대원 1",
                isReady: false,
                lastActiveAt: Timestamp.now(),
                uid: MEMBER,
                pin: PIN,
            });
        }
        if (recording) {
            await setDoc(doc(db, "sessions", SESSION_ID, "recordings", RECORDING_ID), {
                identity: { sessionID: SESSION_ID, memberID: MEMBER_ID, recordingID: RECORDING_ID },
                state: "recording",
                lastActiveAt: Timestamp.now(),
            });
        }
    });
}

export const MB = 1024 * 1024;

export function bytes(size) {
    return new Uint8Array(size);
}
