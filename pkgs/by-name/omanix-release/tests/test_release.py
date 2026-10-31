"""omanix-release with throwaway keys: SHA256SUMS signing and verification,
tamper and signer refusals, tree-sums, tag verification."""

import json
import os
import subprocess

import pytest

import omanix_release as r


def keygen(path, comment):
    subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-C", comment, "-f", str(path)], check=True)
    return " ".join(open(f"{path}.pub").read().split()[:2])


@pytest.fixture
def keys(tmp_path):
    good, bad = tmp_path / "release", tmp_path / "other"
    pub = keygen(good, "release@test")
    keygen(bad, "other@test")
    signers = tmp_path / "allowed_signers"
    signers.write_text(f'release@test namespaces="git,omanix-release" {pub}\n')
    return good, bad, signers


def release_dir(tmp_path, key):
    d = tmp_path / "rel"
    d.mkdir()
    (d / "omanix-installer-0.1.0.raw").write_bytes(os.urandom(4096))
    (d / "release.json").write_text(json.dumps({"version": "0.1.0", "tag": "v0.1.0", "commit": "c" * 40,
                                                "images": {"offline": {"file": "omanix-installer-0.1.0.raw"}}}))
    r.write_sums(str(d))
    r.sign(str(d / "SHA256SUMS"), str(key))
    return d


def test_verify_ok(tmp_path, keys):
    good, _, signers = keys
    d = release_dir(tmp_path, good)
    res = r.verify(str(d), str(signers))
    assert res["signer"] == "release@test" and res["tag"] == "v0.1.0"


def test_tampered_image(tmp_path, keys):
    good, _, signers = keys
    d = release_dir(tmp_path, good)
    with open(d / "omanix-installer-0.1.0.raw", "r+b") as f:
        f.write(b"x")
    with pytest.raises(r.ReleaseError, match="doesn't match"):
        r.verify(str(d), str(signers))


def test_other_signer(tmp_path, keys):
    _, bad, signers = keys
    d = release_dir(tmp_path, bad)
    with pytest.raises(r.ReleaseError, match="not by a pinned release signer"):
        r.verify(str(d), str(signers))


def test_unlisted_file(tmp_path, keys):
    good, _, signers = keys
    d = release_dir(tmp_path, good)
    (d / "extra.sh").write_text("echo hi\n")
    with pytest.raises(r.ReleaseError, match="not covered"):
        r.verify(str(d), str(signers))


def test_empty_signers(tmp_path, keys):
    good, _, _ = keys
    d = release_dir(tmp_path, good)
    empty = tmp_path / "empty"
    empty.write_text("# pin the release key here\n")
    with pytest.raises(r.ReleaseError, match="lists no signer"):
        r.verify(str(d), str(empty))


def test_wrong_namespace(tmp_path, keys):
    good, _, signers = keys
    d = release_dir(tmp_path, good)
    os.unlink(d / "SHA256SUMS.sig")
    subprocess.run(["ssh-keygen", "-Y", "sign", "-q", "-f", str(good), "-n", "git", str(d / "SHA256SUMS")], check=True)
    with pytest.raises(r.ReleaseError, match="doesn't verify"):
        r.verify(str(d), str(signers))


def test_tree_sums(tmp_path):
    for p in ("scripts/a.sh", "pkgs/x/y.nix", "flake.nix", ".git/HEAD", "pkgs/__pycache__/c.pyc", "scripts/SHA256SUMS.sig"):
        (tmp_path / p).parent.mkdir(parents=True, exist_ok=True)
        (tmp_path / p).write_text(p)
    assert r.tree_sums(str(tmp_path)) == 3
    names = [line.split("  ", 1)[1].strip() for line in open(tmp_path / "scripts/SHA256SUMS")]
    assert names == ["flake.nix", "pkgs/x/y.nix", "scripts/a.sh"]


def git(repo, *args, **kw):
    return subprocess.run(["git", "-C", str(repo), *args], check=True, capture_output=True, text=True, **kw).stdout


def test_verify_tag(tmp_path, keys):
    good, bad, signers = keys
    repo = tmp_path / "repo"
    (repo / "release").mkdir(parents=True)
    (repo / "release/allowed_signers").write_text(signers.read_text())
    (repo / "VERSION").write_text("0.1.0\n")
    git(repo, "init", "-q", "-b", "master")
    git(repo, "add", "-A")
    ident = ["-c", "user.name=t", "-c", "user.email=t@t", "-c", "gpg.format=ssh"]
    git(repo, *ident, "commit", "-q", "-m", "release")
    git(repo, *ident, "-c", f"user.signingKey={good}", "tag", "-s", "-m", "v0.1.0", "v0.1.0")
    commit, _ = r.verify_tag(str(repo), "v0.1.0")
    assert commit == git(repo, "rev-parse", "HEAD").strip()
    git(repo, *ident, "-c", f"user.signingKey={bad}", "tag", "-s", "-m", "bad", "v0.1.1")
    with pytest.raises(r.ReleaseError, match="isn't signed"):
        r.verify_tag(str(repo), "v0.1.1")
    git(repo, *ident, "tag", "-a", "-m", "unsigned", "v0.1.2")
    with pytest.raises(r.ReleaseError, match="isn't signed"):
        r.verify_tag(str(repo), "v0.1.2")
