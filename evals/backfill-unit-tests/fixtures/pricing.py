def apply_discount(price: int, percent: int) -> int:
    """Return integer price after subtracting percent (0-100)."""
    return price * (100 - percent) // 100


def tax_inclusive(net: int, rate: int) -> int:
    """Return integer net plus tax rate (0-100)."""
    return net * (100 + rate) // 100
