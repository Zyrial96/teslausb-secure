#!/usr/bin/env python3
"""
Auto-generated test suite for teslausb-secure skill
Run: python3 test_skill.py
"""

import sys
import subprocess
from pathlib import Path

SKILL_DIR = Path(__file__).parent.parent
sys.path.insert(0, str(SKILL_DIR))

def run_skill_check(args, expected_in_output=None):
    """Run skill and check output"""
    # This is a simplified check - customize based on skill
    result = subprocess.run(
        ["python3", "-c", f"print('Skill: teslausb-secure')"],
        capture_output=True, text=True, timeout=10
    )
    
    if expected_in_output:
        return expected_in_output in result.stdout or expected_in_output in result.stderr
    return result.returncode == 0

# --- Tests ---

def test_skill_exists():
    """SKILL.md must exist"""
    skill_file = SKILL_DIR / "SKILL.md"
    assert skill_file.exists(), "SKILL.md not found"
    return True

def test_skill_has_frontmatter():
    """SKILL.md must have YAML frontmatter"""
    content = (SKILL_DIR / "SKILL.md").read_text()
    assert "---" in content[:10], "Missing YAML frontmatter"
    assert "name:" in content, "Missing 'name' in frontmatter"
    assert "description:" in content, "Missing 'description' in frontmatter"
    return True

def test_skill_has_content():
    """SKILL.md must have meaningful content"""
    content = (SKILL_DIR / "SKILL.md").read_text()
    lines = [l for l in content.split('\n') if l.strip() and not l.startswith('#')]
    assert len(lines) > 20, "SKILL.md too short (< 20 content lines)"
    return True

def test_skill_no_placeholders():
    """SKILL.md should not have TODO/placeholder text"""
    content = (SKILL_DIR / "SKILL.md").read_text().lower()
    bad_words = ['todo', 'fixme', 'placeholder', 'xxx', 'insert here']
    for word in bad_words:
        assert word not in content, f"Found placeholder: {word}"
    return True

def test_skill_examples_present():
    """SKILL.md should have code examples"""
    content = (SKILL_DIR / "SKILL.md").read_text()
    has_code = '```' in content or '    ' in content
    assert has_code, "No code examples found"
    return True

# --- Run All Tests ---

TESTS = [
    test_skill_exists,
    test_skill_has_frontmatter,
    test_skill_has_content,
    test_skill_no_placeholders,
    test_skill_examples_present,
]

if __name__ == "__main__":
    passed = 0
    failed = 0
    
    for test in TESTS:
        try:
            test()
            print(f"✅ {test.__name__}")
            passed += 1
        except AssertionError as e:
            print(f"❌ {test.__name__}: {e}")
            failed += 1
        except Exception as e:
            print(f"💥 {test.__name__}: {e}")
            failed += 1
    
    print(f"\n{passed}/{len(TESTS)} tests passed")
    
    # Output score for auto-research
    score = passed / len(TESTS)
    print(f"SCORE: {score:.2f}")
    
    sys.exit(0 if failed == 0 else 1)
