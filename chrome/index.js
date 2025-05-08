const puppeteer = require('puppeteer-core');

(async () => {
  const browserURL = 'http://127.0.0.1:9222'; // Đây là cổng bạn đã mở ở Bước 1
  const websiteUrl = 'https://www.riffusion.com/';

  try {
    console.log('Đang kết nối tới trình duyệt hiện tại...');
    // Kết nối với instance Chrome đang chạy
    const browser = await puppeteer.connect({ browserURL, defaultViewport: null });
    const pages = await browser.pages();
    // Sử dụng tab đầu tiên nếu có, nếu không thì tạo tab mới
    const page = pages.length > 0 ? pages[0] : await browser.newPage();

    console.log(`Đang điều hướng tới ${websiteUrl}...`);
    await page.goto(websiteUrl, { waitUntil: 'networkidle2' });

    console.log('Đã tải trang xong. Đang lấy cookies...');
    const cookies = await page.cookies();

    if (cookies.length > 0) {
      console.log('Cookies đã lấy được:');
      cookies.forEach(cookie => {
        console.log(`  - ${cookie.name}: ${cookie.value}`);
      });
    } else {
      console.log('Không tìm thấy cookie nào cho trang này.');
    }

    // Bạn có thể bỏ qua việc đóng trình duyệt nếu muốn giữ nó mở
    // await browser.disconnect();
    // console.log('Đã ngắt kết nối khỏi trình duyệt.');

  } catch (error) {
    console.error('Đã xảy ra lỗi:', error);
    console.log('Hãy đảm bảo bạn đã khởi động Chrome với lệnh --remote-debugging-port=9222');
  }
})();
