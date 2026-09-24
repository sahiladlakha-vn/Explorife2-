"""
One-off dev tool: sanity-check that assets/video/hero-optimized.mp4 loops
seamlessly (no visible jump-cut when it restarts).

It does NOT prove motion is continuous (that still needs your eyes), but it
does two useful things automatically:
  1. Saves the first frame and the last frame as PNGs side-by-side so you can
     eyeball them for an obvious hard cut (different lighting/composition/
     subject position).
  2. Prints a numeric difference score between those two frames. A seamless
     loop usually has a LOW score (the last frame's content should be close
     to the first frame's, since the video is meant to restart into it).
     A very high score is a strong signal of a hard cut.

Usage (from the repo root, in the VS Code integrated terminal):
    pip install opencv-python-headless
    python3 scripts/check_loop_seam.py

Output:
    scripts/_seam_check/first_frame.png
    scripts/_seam_check/last_frame.png
    scripts/_seam_check/side_by_side.png   <- open this one first
    a printed "mean absolute pixel difference" score
"""
import os
import sys

VIDEO_PATH = os.path.join(os.path.dirname(__file__), "..", "assets", "video", "hero-optimized.mp4")
OUT_DIR = os.path.join(os.path.dirname(__file__), "_seam_check")


def main():
    try:
        import cv2
        import numpy as np
    except ImportError:
        print("Missing dependency. Run this first:\n    pip install opencv-python-headless")
        sys.exit(1)

    if not os.path.exists(VIDEO_PATH):
        print(f"Video not found at {VIDEO_PATH}")
        sys.exit(1)

    cap = cv2.VideoCapture(VIDEO_PATH)
    if not cap.isOpened():
        print("OpenCV could not open the video (codec support issue?).")
        sys.exit(1)

    fps = cap.get(cv2.CAP_PROP_FPS) or 30
    frame_count = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
    duration = frame_count / fps if fps else 0
    print(f"fps={fps:.2f}  frame_count={frame_count}  duration={duration:.2f}s")

    # First frame
    ok, first = cap.read()
    if not ok:
        print("Could not read the first frame.")
        sys.exit(1)

    # Last decodable frame — seek near the end and walk forward, since exact
    # frame-count seeking on compressed video is unreliable.
    last = None
    cap.set(cv2.CAP_PROP_POS_FRAMES, max(0, frame_count - 5))
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        last = frame
    if last is None:
        print("Could not read a last frame.")
        sys.exit(1)

    os.makedirs(OUT_DIR, exist_ok=True)
    cv2.imwrite(os.path.join(OUT_DIR, "first_frame.png"), first)
    cv2.imwrite(os.path.join(OUT_DIR, "last_frame.png"), last)

    # Side-by-side for quick visual comparison in VS Code's image preview.
    last_resized = cv2.resize(last, (first.shape[1], first.shape[0]))
    side_by_side = np.hstack([first, last_resized])
    cv2.imwrite(os.path.join(OUT_DIR, "side_by_side.png"), side_by_side)

    # Simple similarity score: mean absolute pixel difference (0-255 scale).
    diff = cv2.absdiff(first, last_resized)
    score = float(np.mean(diff))
    print(f"\nMean absolute pixel difference (first vs. last frame): {score:.2f} / 255")
    if score < 15:
        print("-> Looks continuous (low difference). Likely a clean loop, but still eyeball side_by_side.png.")
    elif score < 35:
        print("-> Some difference — could be normal motion, could be a soft seam. Check side_by_side.png closely.")
    else:
        print("-> High difference — strong signal of a visible jump-cut. Check side_by_side.png; likely needs a re-trim/crossfade.")

    print(f"\nOpen this in VS Code to look: {os.path.join(OUT_DIR, 'side_by_side.png')}")


if __name__ == "__main__":
    main()
