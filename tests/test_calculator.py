import sys
from pathlib import Path

sys.path.append(str(Path(__file__).resolve().parents[1]))

from src.calculator import add


def test_add():
    assert add(2, 3) == 5