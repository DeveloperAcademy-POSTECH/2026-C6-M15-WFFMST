// firebase/storage.rules 테스트
import { randomUUID } from "node:crypto";
import { after, before, beforeEach, describe, test } from "node:test";
import { assertFails, assertSucceeds } from "@firebase/rules-unit-testing";
import { deleteObject, getBytes, ref, uploadBytes } from "firebase/storage";
import {
    INSTRUCTOR, MB, MEMBER, RECORDING_ID, SESSION_ID, STRANGER,
    bytes, createEnvironment, seed,
} from "./support.mjs";

let env;
before(async () => { env = await createEnvironment(); });
after(async () => { await env.cleanup(); });
beforeEach(async () => {
    await env.clearFirestore();
    await env.clearStorage();
});

const storage = (uid) => (uid ? env.authenticatedContext(uid) : env.unauthenticatedContext()).storage();
const file = (uid, path) => ref(storage(uid), path);

describe("도면 파일", () => {
    // 도면은 한 번만 올릴 수 있어 테스트마다 다른 도면 ID를 쓴다.
    let image;
    beforeEach(() => { image = `floorPlans/${randomUUID()}/original.png`; });

    test("로그인한 사용자가 한 번 올리고 읽는다", async () => {
        await assertSucceeds(uploadBytes(file(INSTRUCTOR, image), bytes(1024), { contentType: "image/png" }));
        await assertSucceeds(getBytes(file(MEMBER, image)));
    });

    test("이미 올린 도면은 덮어쓰거나 지울 수 없다", async () => {
        await uploadBytes(file(INSTRUCTOR, image), bytes(1024), { contentType: "image/png" });
        await assertFails(uploadBytes(file(INSTRUCTOR, image), bytes(1024), { contentType: "image/png" }));
        await assertFails(deleteObject(file(INSTRUCTOR, image)));
    });

    test("20MB를 넘는 도면은 올릴 수 없다", async () => {
        await assertFails(uploadBytes(file(INSTRUCTOR, image), bytes(20 * MB + 1), { contentType: "image/png" }));
    });

    test("로그인하지 않으면 올리거나 읽을 수 없다", async () => {
        await assertFails(uploadBytes(file(null, image), bytes(1024), { contentType: "image/png" }));
        await uploadBytes(file(INSTRUCTOR, image), bytes(1024), { contentType: "image/png" });
        await assertFails(getBytes(file(null, image)));
    });
});

describe("보정 결과와 영상", () => {
    const base = `sessions/${SESSION_ID}/recordings/${RECORDING_ID}`;
    const result = `${base}/result.json`;
    const chunk = `${base}/video/chunk_0000.mp4`;

    beforeEach(async () => { await seed(env); });

    test("기록 주인이 보정 결과와 영상을 올린다", async () => {
        await assertSucceeds(uploadBytes(file(MEMBER, result), bytes(1024), { contentType: "application/json" }));
        await assertSucceeds(uploadBytes(file(MEMBER, chunk), bytes(1024), { contentType: "video/mp4" }));
    });

    test("다른 사람과 교관은 기록 파일을 올릴 수 없다", async () => {
        await assertFails(uploadBytes(file(STRANGER, chunk), bytes(1024), { contentType: "video/mp4" }));
        await assertFails(uploadBytes(file(INSTRUCTOR, chunk), bytes(1024), { contentType: "video/mp4" }));
    });

    test("20MB를 넘는 영상 조각은 올릴 수 없다", async () => {
        await assertFails(uploadBytes(file(MEMBER, chunk), bytes(20 * MB + 1), { contentType: "video/mp4" }));
    });

    test("교관만 기록 파일을 읽고 지운다", async () => {
        await uploadBytes(file(MEMBER, chunk), bytes(1024), { contentType: "video/mp4" });
        await assertFails(getBytes(file(MEMBER, chunk)));
        await assertFails(deleteObject(file(STRANGER, chunk)));
        await assertSucceeds(getBytes(file(INSTRUCTOR, chunk)));
        await assertSucceeds(deleteObject(file(INSTRUCTOR, chunk)));
    });
});
