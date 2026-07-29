
const { chromium } = require('playwright');
(async () => {
  const browser = await chromium.launch();
  const page = await browser.newPage();
  try {
    await page.goto('http://127.0.0.1:5174/', { waitUntil: 'domcontentloaded', timeout: 20000 });
    console.log('TITLE', await page.title());
    console.log('OK');
  } catch (e) {
    console.log('ERR', e.message);
  }
  await browser.close();
})();
