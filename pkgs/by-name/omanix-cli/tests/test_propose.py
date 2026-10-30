"""omanix propose: the chat's rollback sentence (W21)."""

from omanix_cli.cmd_build import plain_reason


def test_plain_reason_maps_omanix_checks():
    assert plain_reason("health check hyprland-ipc failed within 30 s") == "Hyprland didn't answer within 30 s"
    assert plain_reason("health check hyprland-display failed within 30 s") == "Hyprland lost its display within 30 s"
    assert plain_reason("health check omanix-shell failed within 20 s") == "the desktop shell stopped within 20 s"


def test_plain_reason_keeps_loom_reasons_and_unknown_checks():
    assert plain_reason("units failed: foo.service") == "units failed: foo.service"
    assert plain_reason("health check my-plugin failed within 30 s") == "health check my-plugin failed within 30 s"
    assert plain_reason(None) == "a health check failed"
