#!/usr/bin/env python3
"""Writes the vectors proposed by RFC 0002, in the format of the published corpus.

    python3 rfcs/0002/generate.py [--check]

It reads published vectors as templates, changes one thing in each, and signs with the test keys
whose seeds the corpus publishes. Standard library only: Ed25519 is implemented below from
RFC 8032, because the cases need signatures no library will make. The output is deterministic;
--check fails if the files in rfcs/0002/vectors differ from what would be written.

These are proposals. They are not part of the conformance corpus, and the expectation in each is
what the RFC proposes, not a published expectation.
"""

import base64
import hashlib
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ROOT = HERE.parent.parent
OUT = HERE / "vectors"
STATEMENT_DOMAIN = b"verified:evidence-statement:v1\n"
SPKI = bytes.fromhex("302a300506032b6570032100")

# --- Ed25519, RFC 8032 section 5.1 ------------------------------------------------------------

P = 2**255 - 19
L = 2**252 + 27742317777372353535851937790883648493
D = -121665 * pow(121666, P - 2, P) % P
SQRT_M1 = pow(2, (P - 1) // 4, P)


def add(a, b):
    (x1, y1), (x2, y2) = a, b
    k = D * x1 * x2 * y1 * y2 % P
    return ((x1 * y2 + x2 * y1) * pow(1 + k, P - 2, P) % P, (y1 * y2 + x1 * x2) * pow(1 - k, P - 2, P) % P)


def mul(scalar, point):
    result = (0, 1)
    while scalar:
        if scalar & 1:
            result = add(result, point)
        point = add(point, point)
        scalar >>= 1
    return result


def recover_x(y, sign):
    x2 = (y * y - 1) * pow(D * y * y + 1, P - 2, P) % P
    x = pow(x2, (P + 3) // 8, P)
    if (x * x - x2) % P:
        x = x * SQRT_M1 % P
    if (x * x - x2) % P:
        return None
    return P - x if (x & 1) != sign and x else x


BASE_Y = 4 * pow(5, P - 2, P) % P
BASE = (recover_x(BASE_Y, 0), BASE_Y)
IDENTITY = (0, 1)


def encode(point):
    x, y = point
    return (y | ((x & 1) << 255)).to_bytes(32, "little")


def secret(seed):
    h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little") & ((1 << 254) - 8) | (1 << 254)
    return a, h[32:]


def challenge(r, a, message):
    return int.from_bytes(hashlib.sha512(r + a + message).digest(), "little") % L


def sign(seed, message):
    a, prefix = secret(seed)
    public = encode(mul(a, BASE))
    r = int.from_bytes(hashlib.sha512(prefix + message).digest(), "little") % L
    big_r = encode(mul(r, BASE))
    s = (r + challenge(big_r, public, message) * a) % L
    return big_r + s.to_bytes(32, "little")


def torsion_point():
    """A point of order 8: a generator of the small subgroup."""
    y = 2
    while True:
        x = recover_x(y, 0)
        if x is not None:
            point = mul(L, (x, y))
            if mul(4, point) != IDENTITY:
                return point
        y += 1


# --- verified-json-v1, for the texts used here (ASCII, no control characters) -------------------


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False)


def b64(data):
    return base64.b64encode(data).decode()


def spki(public):
    return b64(SPKI + public)


# --- Templates -----------------------------------------------------------------------------------

SEEDS = {k["keyId"]: bytes.fromhex(k["seedHex"]) for k in json.loads((ROOT / "test-vectors/evidence-statement/v1/keys.json").read_text())["keys"]}
TEMPLATE = json.loads((ROOT / "test-vectors/evidence-statement/v1/valid/statement-genesis.json").read_text())
KEY = TEMPLATE["expected"]["keyId"]
SEED = SEEDS[KEY]
SIGNED = json.loads(TEMPLATE["input"]["signedStatementJson"])
assert canonical(SIGNED) == TEMPLATE["input"]["signedStatementJson"], "the template is not reproduced by this canonicalizer"
assert b64(sign(SEED, STATEMENT_DOMAIN + canonical(SIGNED["statement"]).encode())) == SIGNED["signature"]["encoded"], "the template's signature is not reproduced"


def statement(**changes):
    """The template's statement with members replaced; a dotted name reaches into an object."""
    value = json.loads(canonical(SIGNED["statement"]))
    for name, replacement in changes.items():
        target = value
        *path, last = name.split(".")
        for step in path:
            target = target[step]
        target[last] = replacement
    return value


def signed_text(value, signature, key=KEY):
    return canonical({"signature": {"encoded": signature, "keyId": key, "scheme": "Ed25519"}, "statement": value})


def registry(public=None):
    keys = json.loads(json.dumps(TEMPLATE["registry"]))
    if public is not None:
        for key in keys["keys"]:
            if key["keyId"] == KEY:
                key["publicKey"] = spki(public)
    return keys


VECTORS = []


def vector(folder, name, description, text, error, keys=None):
    VECTORS.append((f"evidence-statement/v1/{folder}/{name}.json", {"description": description, "expected": {"accept": False, "error": error}, "input": {"signedStatementJson": text}, "kind": "statement", "name": name, "protocol": "verified-evidence-statement-v1", "registry": keys or registry()}))


def build():
    value = statement()
    message = STATEMENT_DOMAIN + canonical(value).encode()
    good = sign(SEED, message)
    a, _ = secret(SEED)
    public = encode(mul(a, BASE))

    # 1. S is not reduced: the same signature with the group order added to S.
    s = int.from_bytes(good[32:], "little")
    vector("must-reject", "signature-s-not-reduced", "A valid signature whose S has the group order added to it. RFC 8032 requires S below the order; a verifier that does not check would accept two signatures for one statement.", signed_text(value, b64(good[:32] + (s + L).to_bytes(32, "little"))), "SIGNATURE_INVALID")

    neutral = encode(IDENTITY)

    # 3. R is the neutral element, under an honest key: S = k * a.
    k = challenge(neutral, public, message)
    vector("must-reject", "signature-small-order-r", "Under an honest key, a signature whose R is the neutral element and whose S is the challenge times the secret scalar. It satisfies the RFC 8032 equation and only the key's holder can make it.", signed_text(value, b64(neutral + (k * a % L).to_bytes(32, "little"))), "SIGNATURE_INVALID")

    # 4. R is the neutral element in a non-canonical encoding: y = p + 1.
    odd = (P + 1).to_bytes(32, "little")
    k = challenge(odd, public, message)
    vector("must-reject", "signature-point-not-canonical", "As signature-small-order-r, with R encoded as y = p + 1: the neutral element in an encoding RFC 8032 decoding refuses.", signed_text(value, b64(odd + (k * a % L).to_bytes(32, "little"))), "SIGNATURE_INVALID")

    # 5. A key with a component of order 8. The signature satisfies 8[S]B = 8R + 8[k]A and not
    #    [S]B = R + [k]A, so the two forms of the equation in RFC 8032 disagree about it.
    mixed = encode(add(mul(a, BASE), torsion_point()))
    r = 1
    while True:
        big_r = encode(mul(r, BASE))
        k = challenge(big_r, mixed, message)
        if k % 8:
            break
        r += 1
    vector("must-reject", "signature-cofactored-only", "The registered key has a component of order 8. The signature satisfies the equation of RFC 8032 multiplied by the cofactor, and not the equation without it.", signed_text(value, b64(big_r + ((r + k * a) % L).to_bytes(32, "little"))), "SIGNATURE_INVALID", registry(mixed))

    # 6 to 9. The signature is right and its spelling is not standard, padded base64.
    encoded = b64(good)
    assert encoded.endswith("==")
    stray = encoded[:-3] + "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"["ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/".index(encoded[-3]) | 1] + "=="
    assert stray != encoded and base64.b64decode(stray) == good
    vector("must-reject", "signature-base64-unpadded", "The signature's base64 without its padding.", signed_text(value, encoded.rstrip("=")), "SIGNATURE_INVALID")
    vector("must-reject", "signature-base64-stray-bits", "The signature's base64 with a non-zero bit after the last byte. A lenient decoder yields the same 64 bytes.", signed_text(value, stray), "SIGNATURE_INVALID")
    url = encoded.replace("+", "-").replace("/", "_")
    if url != encoded:
        vector("must-reject", "signature-base64-url-alphabet", "The signature in the URL-safe base64 alphabet.", signed_text(value, url), "SIGNATURE_INVALID")
    vector("must-reject", "signature-wrong-length", "Standard base64 of 63 bytes.", signed_text(value, b64(good[:63])), "SIGNATURE_INVALID")

    # 10. A member twice, with the same value. The text is otherwise the valid statement.
    text = signed_text(value, b64(good))
    twice = text.replace('"scheme":"Ed25519"', '"scheme":"Ed25519","scheme":"Ed25519"')
    assert twice != text
    vector("invalid", "statement-duplicate-member", "The valid statement with one member of `signature` written twice, with the same value.", twice, "MALFORMED")

    # 11 to 13. Spellings that have the shape of an instant and denote none, correctly signed.
    for name, spelled, what in (
        ("statement-time-not-a-date", "2026-02-30T10:00:00Z", "the thirtieth of February"),
        ("statement-time-hour-24", "2026-03-01T24:00:00Z", "hour 24"),
        ("statement-time-leap-second", "2026-06-30T23:59:60Z", "second 60"),
    ):
        changed = statement(**{"observedAt.value": spelled})
        vector("invalid", name, f"`observedAt` is {what}: the shape of an instant, and not the canonical spelling of any. The signature is over this text.", signed_text(changed, b64(sign(SEED, STATEMENT_DOMAIN + canonical(changed).encode()))), "MALFORMED")

    # 14, 15. Sequence numbers outside the range proposed for every protocol integer.
    for name, sequence, what in (
        ("statement-sequence-negative", -1, "below zero"),
        ("statement-sequence-beyond-2-53", 2**53, "2^53, the first integer an IEEE 754 double cannot tell from its neighbour"),
    ):
        changed = statement(**{"chain.sequence": sequence})
        vector("invalid", name, f"`chain.sequence` is {what}. The signature is over this text.", signed_text(changed, b64(sign(SEED, STATEMENT_DOMAIN + canonical(changed).encode()))), "MALFORMED")


def package_vector(folder, name, description, text, error):
    VECTORS.append((f"wvp/v0.2/{folder}/{name}.json", {"description": description, "expected": {"accept": False, "error": error}, "name": name, "packageJson": text, "protocol": "wvp-0.2", "registry": PACKAGE["registry"]}))


PACKAGE = json.loads((ROOT / "test-vectors/wvp/v0.2/valid/supported.json").read_text())


def recommit(package):
    """Sets the package's commitment and identifier to those of its manifest, as section 2 defines."""
    digest = hashlib.sha256(canonical(package["manifest"]).encode()).hexdigest()
    package["packageCommitment"] = {"algorithm": "sha-256", "hex": digest}
    package["packageId"] = f"wvp:sha-256:{digest}"
    return package


def build_packages():
    original = PACKAGE["packageJson"]
    assert canonical(json.loads(original)) == original, "the package template is not reproduced by this canonicalizer"
    assert canonical(recommit(json.loads(original))) == original, "the package template's commitment is not reproduced"

    # A manifest entry whose digest is right and whose algorithm is not the one the protocol uses.
    package = json.loads(original)
    package["manifest"]["files"][0]["hash"]["algorithm"] = "sha-512"
    package_vector("must-reject", "manifest-digest-other-algorithm", "The manifest entry of claim.json states the right 64 hexadecimal digits and names the algorithm `sha-512`. The package's commitment and identifier are those of this manifest.", canonical(recommit(package)), "COMPONENT_DIGEST")

    # A component whose path is a number.
    package = json.loads(original)
    package["files"][0]["path"] = 7
    package_vector("invalid", "component-path-not-text", "The first component's `path` is the number 7.", canonical(package), "MALFORMED_COMPONENT")

    # A member of the package written twice.
    twice = original.replace('"signatures":[]', '"signatures":[],"signatures":[]')
    assert twice != original
    package_vector("invalid", "package-duplicate-member", "The valid package with its `signatures` member written twice, with the same value.", twice, "NOT_CANONICAL")

    # An integer no IEEE 754 double holds exactly, where step 2 reads a number.
    package = json.loads(original)
    package["manifest"]["packageVersion"] = 2**53 + 1
    package_vector("invalid", "package-version-beyond-2-53", "`packageVersion` is 2^53 + 1. The text is canonical: verified-json-v1 allows an integer of any size. A verifier that reads numbers as doubles sees 2^53.", canonical(package), "UNSUPPORTED_VERSION")


def registry_vector(folder, name, description, keys):
    VECTORS.append((f"trust-registry/v1/{folder}/{name}.json", {"description": description, "expected": {"accept": folder == "valid"}, "name": name, "registry": keys}))


def build_registries():
    def entry(keys):
        return next(key for key in keys["keys"] if key["keyId"] == KEY)

    def changed(change):
        keys = registry()
        change(keys, entry(keys))
        return keys

    def rename(key, old, new):
        key[new] = key.pop(old)

    a, _ = secret(SEED)
    public = encode(mul(a, BASE))
    registry_vector("valid", "optional-members-absent", "The entry has no `validUntil` and no `revokedAt` member. It means what `null` means: no end, not revoked.", changed(lambda keys, key: (key.pop("validUntil"), key.pop("revokedAt"))))
    registry_vector("invalid", "key-small-order", "A public key of small order: the neutral element. The signature (neutral element, 0) satisfies the RFC 8032 equation for every message under it.", registry(encode(IDENTITY)))
    registry_vector("invalid", "key-order-eight", "A public key of order 8.", registry(encode(torsion_point())))
    registry_vector("invalid", "key-point-not-canonical", "The neutral element encoded as y = p + 1, which RFC 8032 decoding refuses.", registry((P + 1).to_bytes(32, "little")))
    registry_vector("invalid", "key-base64-unpadded", "A good key whose base64 has no padding.", changed(lambda keys, key: key.update(publicKey=spki(public).rstrip("="))))
    registry_vector("invalid", "key-not-subject-public-key-info", "The 32 bytes of a good key in base64, without the RFC 8410 structure around them.", changed(lambda keys, key: key.update(publicKey=b64(public))))
    registry_vector("invalid", "member-unknown", "`revokedAt` is misspelt `revokedAT`. Read leniently, the key is not revoked.", changed(lambda keys, key: (key.pop("revokedAt"), key.update(revokedAT={"value": "2026-06-01T00:00:00Z"}))))
    registry_vector("invalid", "key-id-twice", "Two entries with one key ID.", changed(lambda keys, key: keys["keys"].append(dict(keys["keys"][1], keyId=KEY))))
    registry_vector("invalid", "public-key-twice", "Two entries with one public key.", changed(lambda keys, key: keys["keys"].append(dict(key, keyId="another-id"))))
    registry_vector("invalid", "time-not-canonical", "`validFrom` is an instant in a spelling that is not the canonical one.", changed(lambda keys, key: key.update(validFrom={"value": "2026-01-01T00:00:00.000Z"})))


def build_canonical():
    """Cases to add to the `invalid` list of canonical-hash-v1.json: texts that are not the encoding of a value."""
    cases = [
        ("duplicate-member-same-value", '{"a":1,"a":1}'),
        ("duplicate-member-other-value", '{"a":1,"a":2}'),
        ("duplicate-member-nested", '{"a":{"b":1,"b":1}}'),
        ("duplicate-member-by-escape", '{"a":1,"\\u0061":2}'),
    ]
    VECTORS.append(("canonical-hash-v1.additions.json", {"description": "Cases RFC 0002 proposes to add to the `invalid` list of canonical-hash-v1.json.", "invalid": [{"name": name, "inputJson": text} for name, text in cases]}))


def main():
    build()
    build_packages()
    build_registries()
    build_canonical()
    stale = []
    for path, value in VECTORS:
        text = json.dumps(value, indent=2, ensure_ascii=False) + "\n"
        file = OUT / path
        if "--check" in sys.argv:
            if not file.is_file() or file.read_text(encoding="utf-8") != text:
                stale.append(path)
        else:
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_text(text, encoding="utf-8")
    if stale:
        sys.exit("not as generated: " + ", ".join(stale))
    print(f"{len(VECTORS)} proposed vectors {'are as generated' if '--check' in sys.argv else 'written'}.")


if __name__ == "__main__":
    main()
