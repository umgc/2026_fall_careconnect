
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  await page.goto('http://127.0.0.1:5174/', { waitUntil: 'domcontentloaded', timeout: 20000 });
  await page.evaluate(() => { localStorage.clear(); sessionStorage.clear(); });
  await page.reload({ waitUntil: 'domcontentloaded' });
  await page.getByRole('button', { name: /log in as patient/i }).click();
  await page.waitForTimeout(1000);
  console.log('AFTER LOGIN CLICK');
  console.log('BUTTONS', JSON.stringify((await page.locator('button').allTextContents()).slice(0,60)));
  console.log('BODY', (await page.locator('body').innerText()).slice(0,2500));
  await browser.close();
})();
