"""Install isolated, pinned SDK environments, then validate the downloaded model."""
import argparse, hashlib, os, subprocess, sys
from pathlib import Path

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    parser.add_argument("--engine", choices=["vieneu", "qwen"], required=True)
    parser.add_argument("--resources", type=Path, required=True)
    args = parser.parse_args()
    try: os.setsid()
    except OSError: pass
    marker = args.root / "Models" / args.engine / "installed.json"
    marker.unlink(missing_ok=True)  # An interrupted SDK/model update must never look ready.
    requirements = args.resources / (args.engine + "-requirements.txt")
    digest = hashlib.sha256(requirements.read_bytes()).hexdigest()
    env = args.root / "Environments" / args.engine
    python = env / "bin" / "python3"
    os.environ["PIP_DISABLE_PIP_VERSION_CHECK"] = "1"
    os.environ["PYTHONDONTWRITEBYTECODE"] = "1"
    if not python.exists():
        print("Preparing isolated runtime", file=sys.stderr, flush=True)
        subprocess.run([sys.executable, "-m", "venv", str(env)], check=True)
    stamp = env / "requirements.sha256"
    if not stamp.is_file() or stamp.read_text().strip() != digest:
        print("Installing pinned SDK", file=sys.stderr, flush=True)
        subprocess.run([str(python), "-m", "pip", "install", "--no-cache-dir", "--only-binary=:all:", "--index-url", "https://pypi.org/simple", "-r", str(requirements)], check=True, stdout=sys.stderr)
        stamp.write_text(digest)
    print("Downloading and verifying model", file=sys.stderr, flush=True)
    subprocess.run([str(python), str(args.resources / "worker.py"), "--engine", args.engine,
                    "--root", str(args.root / "Models" / args.engine), "--install"], check=True)

if __name__ == "__main__": main()
