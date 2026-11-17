// Kaiten 3D viewer page logic. Loaded by viewer.html via dynamic import
// (static module errors bypass window.onerror — keep that bootstrap).
//
// Page API (stable — SPEC-005/006 build on it):
//   window.kaiten.loadModel(source, format?): Promise — source is a URL
//     string or an ArrayBuffer/TypedArray of model bytes. format is
//     'stl'|'obj'|'3mf'; inferred from the URL extension when omitted
//     (bytes with no format default to 'stl', for selftest compatibility).
//   window.kaiten.getBounds(): {min, max, center, radius, fillRatio} of
//     the last model — fillRatio is the bounding-sphere diameter as a
//     fraction of the viewport's smaller dimension (framing contract: 0.6-0.9).
//
// Events posted to the 'kaiten' script message handler (JSON strings):
//   {event: 'rendered', ms}  {event: 'error', message}
//   {event: 'selftest-case', case, pass, detail}  (per-case, ?selftest=1)
//   {event: 'selftest-pass'} {event: 'selftest-fail', message}  (?selftest=1)

import * as THREE from 'three';
import { STLLoader } from 'three/addons/loaders/STLLoader.js';
import { OBJLoader } from 'three/addons/loaders/OBJLoader.js';
import { ThreeMFLoader } from 'three/addons/loaders/3MFLoader.js';
import { OrbitControls } from 'three/addons/controls/OrbitControls.js';
import { Unzip, UnzipInflate } from 'three/addons/libs/fflate.module.js';

// SPEC-008: preflight caps against decompression/allocation bombs — a
// small on-disk file (SPEC-006's 100 MB check happens before any of
// this) can still claim/produce far more geometry or bytes than it
// should. These are checked *before* the real loaders allocate/inflate,
// not after — see preflightStl / preflight3mfDecompressedSize below.
const MAX_TRIANGLE_COUNT = 5_000_000;
const MAX_VERTEX_COUNT = 5_000_000;
const MAX_3MF_DECOMPRESSED_BYTES = 500 * 1024 * 1024;
const MAX_TEXTURE_BYTES = 20 * 1024 * 1024;
// Mirrors 3MFLoader's own texture-entry path match (vendor/addons/loaders/3MFLoader.js).
const TEXTURE_ENTRY_RE = /^3D\/Textures?\/.*/;

const t0 = performance.now();

function post(msg) {
    try {
        window.webkit.messageHandlers.kaiten.postMessage(JSON.stringify(msg));
    } catch (e) {
        console.log('post failed', e);
    }
}

const params = new URLSearchParams(window.location.search);

const canvas = document.getElementById('canvas');
const renderer = new THREE.WebGLRenderer({ canvas, antialias: true });
renderer.setPixelRatio(window.devicePixelRatio);

const scene = new THREE.Scene();
scene.background = new THREE.Color(0x2d2d2d);

const camera = new THREE.PerspectiveCamera(45, 1, 0.1, 1000);
scene.add(new THREE.AmbientLight(0xffffff, 0.5));
const dirLight = new THREE.DirectionalLight(0xffffff, 1.5);
scene.add(dirLight);

const controls = new OrbitControls(camera, canvas);
controls.enableDamping = true;

let currentRoot = null;
let lastBounds = null;

function resize() {
    const w = canvas.clientWidth, h = canvas.clientHeight;
    renderer.setSize(w, h, false);
    camera.aspect = w / h;
    camera.updateProjectionMatrix();
}
window.addEventListener('resize', resize);

function frameObject(object) {
    const box = new THREE.Box3().setFromObject(object);
    if (box.isEmpty())
        throw new Error('empty geometry');
    const center = box.getCenter(new THREE.Vector3());
    const sphere = box.getBoundingSphere(new THREE.Sphere());
    const radius = Math.max(sphere.radius, 1e-9);

    const fov = THREE.MathUtils.degToRad(camera.fov);
    const dist = (radius / Math.sin(fov / 2)) * 1.15;

    camera.position.copy(center).add(new THREE.Vector3(1, 0.75, 1).normalize().multiplyScalar(dist));
    camera.near = Math.max(dist - radius * 4, radius * 0.01);
    camera.far = dist + radius * 8;
    camera.updateProjectionMatrix();

    controls.target.copy(center);
    controls.update();

    dirLight.position.copy(camera.position);

    // Fraction of the viewport's smaller dimension the bounding-sphere
    // diameter occupies at the framed distance — framing contract is 0.6-0.9.
    const vHalfExtent = dist * Math.tan(fov / 2);
    const hHalfExtent = vHalfExtent * camera.aspect;
    const fillRatio = radius / Math.min(vHalfExtent, hHalfExtent);

    lastBounds = {
        min: box.min.toArray(),
        max: box.max.toArray(),
        center: center.toArray(),
        radius,
        fillRatio,
    };
}

let animating = false;
function animate() {
    if (!animating) {
        animating = true;
        const tick = () => {
            controls.update();
            dirLight.position.copy(camera.position);
            renderer.render(scene, camera);
            requestAnimationFrame(tick);
        };
        tick();
    }
}

function toArrayBuffer(source) {
    return source instanceof ArrayBuffer
        ? source
        : source.buffer.slice(source.byteOffset, source.byteOffset + source.byteLength);
}

// Uniform entry point for both code paths (a URL string via our own
// kaiten:// scheme, or raw bytes for the selftest) — resolving to an
// ArrayBuffer *before* handing it to a loader is what makes the
// preflight checks below possible; loader.loadAsync() alone never gives
// us the bytes to inspect first.
async function fetchBytes(source) {
    if (typeof source !== 'string')
        return toArrayBuffer(source);
    const res = await fetch(source);
    if (!res.ok)
        throw new Error(`fetch failed: ${res.status} ${res.statusText}`);
    return res.arrayBuffer();
}

// Mirrors STLLoader's own isBinary() text-sniff (checks up to 5 possible
// offsets for a leading "solid", tolerating BOM prefixes) — needed so
// the binary-only preflight below doesn't misfire on a legitimate ASCII
// STL, whose byte 80-83 has no meaningful "face count" to check.
function looksLikeAsciiStl(buffer) {
    const bytes = new Uint8Array(buffer);
    const solid = [115, 111, 108, 105, 100]; // 's' 'o' 'l' 'i' 'd'
    for (let off = 0; off < 5 && off + 5 <= bytes.length; off++) {
        let match = true;
        for (let i = 0; i < 5; i++) {
            if (bytes[off + i] !== solid[i]) { match = false; break; }
        }
        if (match)
            return true;
    }
    return false;
}

const STL_HEADER_BYTES = 84;
const STL_FACE_RECORD_BYTES = 12 * 4 + 2; // normal+3 verts (12 floats) + attr count

// SPEC-008: binary STL's claimed face count (header byte 80, uint32 LE)
// drives STLLoader's vertex/normal Float32Array allocation *before* it
// checks whether the file actually contains that many bytes. Reject
// here, before that allocation ever happens, rather than after.
function preflightStl(buffer) {
    if (buffer.byteLength < STL_HEADER_BYTES || looksLikeAsciiStl(buffer))
        return; // not a binary-STL claim we can check; parser handles it.
    const faceCount = new DataView(buffer).getUint32(80, true);
    const requiredBytes = STL_HEADER_BYTES + faceCount * STL_FACE_RECORD_BYTES;
    if (requiredBytes > buffer.byteLength) {
        throw new Error(
            `STL header claims ${faceCount} faces (needs ${requiredBytes} bytes) ` +
            `but the file is only ${buffer.byteLength} bytes`);
    }
    if (faceCount > MAX_TRIANGLE_COUNT) {
        throw new Error(`STL has ${faceCount} faces, over the ${MAX_TRIANGLE_COUNT} preview limit`);
    }
}

// SPEC-008: 3MFLoader's own unzipSync() call inflates every archive
// member fully, synchronously, before any triangle count is known — the
// zip-bomb shape (tiny compressed, huge decompressed). This walks the
// same archive through fflate's incremental Unzip/UnzipInflate classes
// instead, feeding the *compressed* container in bounded chunks so the
// decompressed-byte tally is checked as output arrives, not after the
// whole archive is in memory. UnzipInflate.push() catches whatever its
// inner Inflate throws and re-delivers it to ondata as an error instead
// of propagating — so our cap-exceeded throw must happen on the *next*
// ondata call (where it arrives as `err`) to actually escape.
function preflight3mfDecompressedSize(buffer) {
    let total = 0;
    const unzip = new Unzip((file) => {
        const isTexture = TEXTURE_ENTRY_RE.test(file.name);
        let entryBytes = 0;
        file.ondata = (err, data, final) => {
            if (err)
                throw err;
            if (data) {
                total += data.length;
                if (isTexture)
                    entryBytes += data.length;
            }
            if (isTexture && entryBytes > MAX_TEXTURE_BYTES) {
                throw new Error(
                    `3MF texture '${file.name}' decompresses past ${MAX_TEXTURE_BYTES} ` +
                    'bytes — too large for quick preview');
            }
            if (total > MAX_3MF_DECOMPRESSED_BYTES) {
                throw new Error(
                    `3MF archive decompresses past ${MAX_3MF_DECOMPRESSED_BYTES} bytes — ` +
                    'too large for quick preview');
            }
        };
        file.start();
    });
    unzip.register(UnzipInflate);

    const bytes = new Uint8Array(buffer);
    const CHUNK_BYTES = 64 * 1024;
    if (bytes.length === 0) {
        unzip.push(bytes, true);
        return;
    }
    for (let off = 0; off < bytes.length; off += CHUNK_BYTES) {
        const end = Math.min(off + CHUNK_BYTES, bytes.length);
        unzip.push(bytes.subarray(off, end), end === bytes.length);
    }
}

// SPEC-008: uniform post-parse cap across STL/3MF/OBJ — bounds what a
// legitimately-shaped (not lying-about-its-size) file can still cost,
// independent of the format-specific preflight checks above.
function tallyGeometry(node, counts) {
    const tally = (geometry) => {
        const pos = geometry.getAttribute && geometry.getAttribute('position');
        if (!pos)
            return;
        counts.vertices += pos.count;
        const index = geometry.getIndex && geometry.getIndex();
        counts.triangles += (index ? index.count : pos.count) / 3;
    };
    if (node.isBufferGeometry) {
        tally(node);
        return;
    }
    node.traverse((child) => {
        if (child.geometry)
            tally(child.geometry);
    });
}

function enforceGeometryCaps(rootOrGeometry) {
    const counts = { vertices: 0, triangles: 0 };
    tallyGeometry(rootOrGeometry, counts);
    if (counts.vertices > MAX_VERTEX_COUNT || counts.triangles > MAX_TRIANGLE_COUNT) {
        if (rootOrGeometry.isBufferGeometry)
            rootOrGeometry.dispose();
        else
            disposeObject(rootOrGeometry);
        throw new Error(
            `Model has ${Math.round(counts.triangles)} triangles / ${counts.vertices} ` +
            `vertices, over the ${MAX_TRIANGLE_COUNT}/${MAX_VERTEX_COUNT} preview limit`);
    }
    return rootOrGeometry;
}

function extensionOf(source) {
    if (typeof source !== 'string')
        return 'stl';
    const clean = source.split('?')[0].split('#')[0];
    const m = /\.([a-z0-9]+)$/i.exec(clean);
    return m ? m[1].toLowerCase() : 'stl';
}

function disposeObject(object) {
    object.traverse((child) => {
        if (!child.isMesh)
            return;
        child.geometry.dispose();
        const materials = Array.isArray(child.material) ? child.material : [child.material];
        materials.forEach((m) => m && m.dispose());
    });
}

function showObject(root) {
    if (currentRoot) {
        scene.remove(currentRoot);
        disposeObject(currentRoot);
    }
    currentRoot = root;
    scene.add(currentRoot);

    resize();
    frameObject(currentRoot);
    renderer.render(scene, camera);
    post({ event: 'rendered', ms: performance.now() - t0 });
    animate();
}

async function loadStl(source) {
    const buffer = await fetchBytes(source);
    preflightStl(buffer);
    const loader = new STLLoader();
    const geometry = enforceGeometryCaps(loader.parse(buffer));
    geometry.computeVertexNormals();
    const material = new THREE.MeshStandardMaterial({
        color: 0x8899cc, metalness: 0.1, roughness: 0.75,
    });
    return new THREE.Mesh(geometry, material);
}

async function loadObj(source) {
    const buffer = await fetchBytes(source);
    const loader = new OBJLoader();
    return enforceGeometryCaps(loader.parse(new TextDecoder().decode(buffer)));
}

async function load3mf(source) {
    const buffer = await fetchBytes(source);
    preflight3mfDecompressedSize(buffer);
    const loader = new ThreeMFLoader();
    return enforceGeometryCaps(loader.parse(buffer));
}

// source: URL string, or ArrayBuffer/TypedArray of model bytes (bytes
// default to STL — used by the selftest, which has no URL to infer from).
async function loadModel(source, format) {
    const ext = (format || extensionOf(source)).toLowerCase();
    let root;
    if (ext === 'obj')
        root = await loadObj(source);
    else if (ext === '3mf')
        root = await load3mf(source);
    else
        root = await loadStl(source);
    showObject(root);
}

function getBounds() {
    return lastBounds;
}

window.kaiten = { loadModel, getBounds };

// 284-byte binary STL tetrahedron: vertices (0,0,0) (1,0,0) (0,1,0) (0,0,1).
const SELFTEST_STL_B64 =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' +
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA' +
    'AACAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA/' +
    'AAAAAAAAAAAAAAAAAAAAAAAAgD8AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAIA/' +
    'AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAA' +
    'AAAAAAAAAAAAAIA/AAA=';

function b64ToBuffer(b64) {
    const bin = atob(b64);
    const bytes = new Uint8Array(bin.length);
    for (let i = 0; i < bin.length; i++)
        bytes[i] = bin.charCodeAt(i);
    return bytes.buffer;
}

function approx(a, b, eps = 1e-3) {
    return Math.abs(a - b) <= eps;
}

function makeCube(scale, offset) {
    const geometry = new THREE.BoxGeometry(2 * scale, 2 * scale, 2 * scale);
    const material = new THREE.MeshStandardMaterial({ color: 0x8899cc });
    const mesh = new THREE.Mesh(geometry, material);
    mesh.position.set(offset[0], offset[1], offset[2]);
    return mesh;
}

// Framing contract: projected bounding-sphere diameter is 60-90% of the
// viewport's smaller dimension, and the orbit target is the bbox center.
function checkFraming(caseName, root, expectedCenter) {
    showObject(root);
    const b = getBounds();
    const centerOk = expectedCenter.every((v, i) => approx(b.center[i], v));
    const fillOk = b.fillRatio >= 0.6 && b.fillRatio <= 0.9;
    const pass = centerOk && fillOk;
    post({
        event: 'selftest-case',
        case: caseName,
        pass,
        detail: `center=${JSON.stringify(b.center)} fillRatio=${b.fillRatio.toFixed(3)} centerOk=${centerOk} fillOk=${fillOk}`,
    });
    return pass;
}

async function selftest() {
    try {
        // Base case: original tiny tetrahedron STL, via the real bytes path.
        await loadModel(b64ToBuffer(SELFTEST_STL_B64));
        const b = getBounds();
        const boundsOk =
            [0, 0, 0].every((v, i) => approx(b.min[i], v)) &&
            [1, 1, 1].every((v, i) => approx(b.max[i], v)) &&
            [0.5, 0.5, 0.5].every((v, i) => approx(b.center[i], v));
        const fillOk = b.fillRatio >= 0.6 && b.fillRatio <= 0.9;
        let pass = boundsOk && fillOk;
        post({
            event: 'selftest-case',
            case: 'stl-base',
            pass,
            detail: `bounds=${JSON.stringify(b)} fillRatio=${b.fillRatio.toFixed(3)}`,
        });

        // SPEC-005 hardening: off-origin, tiny (1e-3) and huge (1e6) extents,
        // and a multi-object scene — combined bbox framing must hold for all.
        pass = checkFraming('off-origin', makeCube(1, [50, -30, 20]), [50, -30, 20]) && pass;
        pass = checkFraming('tiny-1e-3', makeCube(0.001, [0, 0, 0]), [0, 0, 0]) && pass;
        pass = checkFraming('huge-1e6', makeCube(1e6, [0, 0, 0]), [0, 0, 0]) && pass;

        const group = new THREE.Group();
        group.add(makeCube(1, [-5, 0, 0]));
        group.add(makeCube(1, [5, 0, 0]));
        pass = checkFraming('two-object', group, [0, 0, 0]) && pass;

        if (pass)
            post({ event: 'selftest-pass' });
        else
            post({ event: 'selftest-fail', message: 'one or more cases failed — see selftest-case events' });
    } catch (e) {
        post({ event: 'selftest-fail', message: String(e) });
    }
}

if (params.get('selftest') === '1') {
    selftest();
} else {
    const modelUrl = params.get('model');
    if (!modelUrl) {
        post({ event: 'error', message: 'no model URL given' });
    } else {
        loadModel(modelUrl, params.get('format')).catch(e =>
            post({ event: 'error', message: String(e) }));
    }
}
