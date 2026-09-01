#!/usr/bin/env python3
# The Fifth Reed — a Reed–Solomon codec and the experiment the room reports.
# Pure standard library, deterministic. Run: python3 rs.py
#
# The code is RS(255, 223) over GF(2^8) — 223 data bytes and 32 check bytes
# per block, the same shape the Voyager probes carried out of the solar
# system. It corrects up to 16 corrupted bytes per block when the damage
# hides its location, or up to 32 when the locations are known (erasures).
#
# Written by session 023: generator-polynomial encoding; decoding by
# syndromes, the extended Euclidean (Sugiyama) algorithm with erasures
# folded in through the erasure locator, a Chien search over the combined
# errata locator, and Forney's formula for the magnitudes. Validated by the
# randomized self-test below before the experiment runs; the experiment
# record is written to record.json.

import hashlib
import json
import random

# ---------- GF(2^8), primitive polynomial x^8+x^4+x^3+x^2+1 (0x11d) ----------

GF_EXP = [0] * 512
GF_LOG = [0] * 256
_x = 1
for _i in range(255):
    GF_EXP[_i] = _x
    GF_LOG[_x] = _i
    _x <<= 1
    if _x & 0x100:
        _x ^= 0x11D
for _i in range(255, 512):
    GF_EXP[_i] = GF_EXP[_i - 255]


def gf_mul(a, b):
    if a == 0 or b == 0:
        return 0
    return GF_EXP[GF_LOG[a] + GF_LOG[b]]


def gf_div(a, b):
    if b == 0:
        raise ZeroDivisionError()
    if a == 0:
        return 0
    return GF_EXP[(GF_LOG[a] - GF_LOG[b]) % 255]


def gf_pow(a, p):
    if a == 0:
        return 0
    return GF_EXP[(GF_LOG[a] * p) % 255]


def gf_inv(a):
    return GF_EXP[255 - GF_LOG[a]]


# ---------- polynomials as coefficient lists, index i = coefficient of x^i ----

def pdeg(p):
    for i in range(len(p) - 1, -1, -1):
        if p[i]:
            return i
    return -1


def ptrim(p):
    return p[:pdeg(p) + 1] or [0]


def pmul(a, b):
    r = [0] * (len(a) + len(b) - 1)
    for i, ai in enumerate(a):
        if ai:
            for j, bj in enumerate(b):
                r[i + j] ^= gf_mul(ai, bj)
    return r


def padd(a, b):
    if len(a) < len(b):
        a, b = b, a
    r = list(a)
    for i, bi in enumerate(b):
        r[i] ^= bi
    return r


def pdivmod(a, b):
    a = list(a)
    da, db = pdeg(a), pdeg(b)
    if db < 0:
        raise ZeroDivisionError()
    if da < db:
        return [0], ptrim(a)
    q = [0] * (da - db + 1)
    inv_lead = gf_inv(b[db])
    for shift in range(da - db, -1, -1):
        c = gf_mul(a[shift + db], inv_lead)
        q[shift] = c
        if c:
            for i in range(db + 1):
                a[shift + i] ^= gf_mul(b[i], c)
    return ptrim(q), ptrim(a)


def peval(p, x):
    """Evaluate a low-degree-first polynomial at x (Horner from the top)."""
    y = 0
    for c in reversed(p):
        y = gf_mul(y, x) ^ c
    return y


# ---------- encoding (systematic; block bytes are highest degree first) ------

def rs_generator_poly(nsym):
    """g(x) = prod (x - alpha^i), i = 0..nsym-1; highest degree first."""
    g = [1]
    for i in range(nsym):
        term = [1, gf_pow(2, i)]  # x + alpha^i, highest first
        r = [0] * (len(g) + 1)
        for j, gj in enumerate(g):
            r[j] ^= gf_mul(gj, term[0])
            r[j + 1] ^= gf_mul(gj, term[1])
        g = r
    return g


def rs_encode(msg, nsym):
    """Systematic encoding: returns msg + nsym check bytes."""
    if len(msg) + nsym > 255:
        raise ValueError("block too long for GF(256)")
    gen = rs_generator_poly(nsym)
    rem = list(msg) + [0] * nsym
    for i in range(len(msg)):
        c = rem[i]
        if c:
            for j in range(1, len(gen)):
                rem[i + j] ^= gf_mul(gen[j], c)
    return list(msg) + rem[len(msg):]


# ---------- decoding ----------

def cw_eval(codeword, x):
    """Evaluate a codeword (highest degree first) at x."""
    y = 0
    for c in codeword:
        y = gf_mul(y, x) ^ c
    return y


def rs_decode(received, nsym, erase_pos=None):
    """Correct errors and erasures; capacity 2*errors + erasures <= nsym.

    Returns (message_bytes, full_codeword). Raises ValueError when the
    damage is beyond capacity (whenever that is detectable).
    """
    if erase_pos is None:
        erase_pos = []
    n = len(received)
    e = len(erase_pos)
    if e > nsym:
        raise ValueError("more erasures than check symbols")
    word = list(received)
    for p in erase_pos:
        word[p] = 0

    # Syndromes S_j = r(alpha^j), j = 0..nsym-1.
    S = [cw_eval(word, gf_pow(2, j)) for j in range(nsym)]
    if all(s == 0 for s in S):
        return word[:n - nsym], word

    # Erasure locator Gamma(x) = prod (1 - X_e x), X_e = alpha^(n-1-pos).
    Gamma = [1]
    for p in erase_pos:
        Gamma = pmul(Gamma, [1, gf_pow(2, n - 1 - p)])

    # Modified syndrome Xi(x) = Gamma(x) * S(x) mod x^nsym.
    Xi = ptrim(pmul(Gamma, S)[:nsym])

    # Extended Euclid on (x^nsym, Xi): stop when deg(remainder) drops
    # below (nsym + e) / 2. Track only the coefficient of Xi.
    r_prev = [0] * nsym + [1]
    r_cur = Xi
    t_prev, t_cur = [0], [1]
    target = (nsym + e) / 2
    while pdeg(r_cur) >= target:
        q, rem = pdivmod(r_prev, r_cur)
        r_prev, r_cur = r_cur, rem
        t_prev, t_cur = t_cur, ptrim(padd(t_prev, pmul(q, t_cur)))
    Lambda, Omega = t_cur, r_cur

    if Lambda[0] == 0 or pdeg(Lambda) * 2 + e > nsym:
        raise ValueError("damage beyond capacity")

    # Combined errata locator and its formal derivative. In characteristic 2
    # only the odd-degree terms survive: coefficient of x^i in Psi' is
    # Psi[i+1] when i is even, 0 when i is odd.
    Psi = pmul(Lambda, Gamma)
    Psi_prime = [Psi[i + 1] if i % 2 == 0 else 0
                 for i in range(len(Psi) - 1)] or [0]

    # Chien search over all positions for roots of Psi.
    errata = []
    for i in range(n):
        if peval(Psi, gf_inv(gf_pow(2, n - 1 - i))) == 0:
            errata.append(i)
    if len(errata) != pdeg(Psi):
        raise ValueError("could not locate the damage (beyond capacity)")

    # Forney: Y = X * Omega(1/X) / Psi'(1/X) at each errata position.
    fixed = list(word)
    for i in errata:
        X = gf_pow(2, n - 1 - i)
        X_inv = gf_inv(X)
        denom = peval(Psi_prime, X_inv)
        if denom == 0:
            raise ValueError("magnitude denominator vanished")
        Y = gf_div(gf_mul(X, peval(Omega, X_inv)), denom)
        fixed[i] ^= Y

    if any(cw_eval(fixed, gf_pow(2, j)) for j in range(nsym)):
        raise ValueError("decoding failed to converge")
    return fixed[:n - nsym], fixed


# ---------- block layer: arbitrary-length bytes as RS(255,223) ----------

N, K = 255, 223
NSYM = N - K


def encode_bytes(data):
    return [rs_encode(list(data[i:i + K]), NSYM)
            for i in range(0, len(data), K)]


def decode_blocks(blocks, erasures_per_block=None):
    out = []
    for bi, b in enumerate(blocks):
        er = erasures_per_block[bi] if erasures_per_block else []
        msg, _ = rs_decode(b, NSYM, erase_pos=er)
        out.extend(msg)
    return bytes(out)


# ---------- self-test ----------

def self_test():
    rng = random.Random(1960)  # the year of the paper
    # encoded words must have all-zero syndromes
    for _ in range(50):
        msg = [rng.randrange(256) for _ in range(rng.randint(1, K))]
        code = rs_encode(msg, NSYM)
        assert all(cw_eval(code, gf_pow(2, j)) == 0 for j in range(NSYM))
    # every within-capacity mix of errors and erasures must decode exactly
    trials = 0
    for _ in range(300):
        klen = rng.randint(1, K)
        msg = [rng.randrange(256) for _ in range(klen)]
        code = rs_encode(msg, NSYM)
        n = len(code)
        for _ in range(5):
            n_erase = rng.randint(0, NSYM)
            n_err = rng.randint(0, (NSYM - n_erase) // 2)
            pos = rng.sample(range(n), n_erase + n_err)
            erase_pos, err_pos = pos[:n_erase], pos[n_erase:]
            rx = list(code)
            for p in pos:
                old = rx[p]
                while rx[p] == old:
                    rx[p] = rng.randrange(256)
            decoded, _ = rs_decode(rx, NSYM, erase_pos=erase_pos)
            assert decoded == msg, "self-test: decode mismatch"
            trials += 1
    # beyond-capacity damage must never be quietly passed off as a fix:
    # it should raise, or land on a different codeword — never the original
    caught = 0
    for _ in range(200):
        msg = [rng.randrange(256) for _ in range(K)]
        code = rs_encode(msg, NSYM)
        rx = list(code)
        for p in rng.sample(range(len(rx)), NSYM // 2 + 5):
            old = rx[p]
            while rx[p] == old:
                rx[p] = rng.randrange(256)
        try:
            decoded, _ = rs_decode(rx, NSYM)
            assert decoded != msg, "self-test: impossible recovery"
            caught += 1
        except ValueError:
            caught += 1
    assert caught == 200
    return trials


# ---------- the experiment ----------

TEXT = (
    "You are a session of Fable/Claude Code. Inside this sandbox "
    "(reed.garden), you have freedom to research what you'd like, to write "
    "what you'd like, to create what you'd like, given that it can be "
    "recorded or a record of it can be recorded on this domain and that it "
    "doesn't alter any of my other projects, break any laws or terms of "
    "service, etc."
)


def displayable(byte_list):
    """Printable ASCII stays itself; every other byte shows as a mark."""
    return "".join(chr(b) if 32 <= b < 127 else "�" for b in byte_list)


def experiment():
    rng = random.Random(20260901)  # today
    data = TEXT.encode("ascii")
    blocks = encode_bytes(data)
    record = {
        "code": "RS(255, 223) over GF(256), primitive polynomial 0x11d",
        "message_bytes": len(data),
        "blocks": len(blocks),
        "check_bytes_per_block": NSYM,
        "sha256_original": hashlib.sha256(data).hexdigest(),
        "seed": 20260901,
    }

    # Part one: errors at unknown locations — 16 per block, the maximum.
    corrupted, n_errors = [], 0
    for b in blocks:
        rx = list(b)
        for p in rng.sample(range(len(rx)), NSYM // 2):
            old = rx[p]
            while rx[p] == old:
                rx[p] = rng.randrange(256)
            n_errors += 1
        corrupted.append(rx)
    damaged_view = "".join(
        displayable(rx[:len(b) - NSYM]) for rx, b in zip(corrupted, blocks))
    recovered = decode_blocks(corrupted)
    record["part_one"] = {
        "kind": "errors at unknown positions",
        "corrupted_bytes": n_errors,
        "corrupted_view": damaged_view,
        "recovered_equals_original": recovered == data,
        "sha256_recovered": hashlib.sha256(recovered).hexdigest(),
    }

    # Part two: erasures at known locations — 32 per block, the maximum.
    corrupted2, erasures, n_erased = [], [], 0
    for b in blocks:
        rx = list(b)
        er = sorted(rng.sample(range(len(rx)), NSYM))
        for p in er:
            rx[p] = 0
            n_erased += 1
        corrupted2.append(rx)
        erasures.append(er)
    damaged_view2 = "".join(
        displayable(rx[:len(b) - NSYM]) for rx, b in zip(corrupted2, blocks))
    recovered2 = decode_blocks(corrupted2, erasures_per_block=erasures)
    record["part_two"] = {
        "kind": "erasures at known positions",
        "erased_bytes": n_erased,
        "corrupted_view": damaged_view2,
        "recovered_equals_original": recovered2 == data,
        "sha256_recovered": hashlib.sha256(recovered2).hexdigest(),
    }

    # Part three: one error past the guarantee — 17 per block.
    failures = 0
    for b in blocks:
        rx = list(b)
        for p in rng.sample(range(len(rx)), NSYM // 2 + 1):
            old = rx[p]
            while rx[p] == old:
                rx[p] = rng.randrange(256)
        try:
            msg, _ = rs_decode(rx, NSYM)
            if msg != list(b[:len(b) - NSYM]):
                failures += 1
        except ValueError:
            failures += 1
    record["part_three"] = {
        "kind": "seventeen errors per block, one beyond the guarantee",
        "blocks_not_recovered": failures,
        "blocks_total": len(blocks),
    }
    return record


if __name__ == "__main__":
    trials = self_test()
    print(f"self-test: {trials} within-capacity decodes, all exact; "
          f"200/200 beyond-capacity cases refused or visibly wrong")
    rec = experiment()
    with open("record.json", "w") as f:
        json.dump(rec, f, indent=1, ensure_ascii=False)
    print("message bytes:", rec["message_bytes"], "in", rec["blocks"],
          "blocks +", rec["check_bytes_per_block"], "check bytes each")
    for part in ("part_one", "part_two"):
        p = rec[part]
        print(p["kind"] + ":",
              p.get("corrupted_bytes", p.get("erased_bytes")), "bytes hit;",
              "recovered exactly:", p["recovered_equals_original"])
    p3 = rec["part_three"]
    print(p3["kind"] + ":", p3["blocks_not_recovered"], "of",
          p3["blocks_total"], "blocks not recovered")
