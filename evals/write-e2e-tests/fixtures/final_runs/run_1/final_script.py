from playwright.sync_api import sync_playwright


def main() -> None:
    with sync_playwright() as p:
        browser = p.firefox.launch(headless=True)
        page = browser.new_page(viewport={"width": 1280, "height": 1800})
        page.goto("https://shop.example.test/catalog")
        page.get_by_role("heading", name="Fixture Widgets").wait_for()
        page.get_by_label("Discount percent").fill("10")
        page.get_by_role("button", name="Apply").click()
        page.get_by_test_id("price-result").wait_for()
        print(page.get_by_test_id("price-result").inner_text())
        browser.close()


if __name__ == "__main__":
    main()
