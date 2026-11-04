# Bật phòng thật bằng Supabase

Khi chưa cấu hình, trang chỉ có phòng mô phỏng như trước. Làm 5 bước dưới đây (khoảng 10 phút) để Key Coach tạo được phòng thật và cả lớp cùng vào.

## 1. Tạo project Supabase

1. Vào https://supabase.com, đăng nhập bằng GitHub.
2. Bấm **New project**. Đặt tên `lop-hoc-lang`, chọn vùng **Southeast Asia (Singapore)**, đặt mật khẩu cơ sở dữ liệu (cất đi, game không dùng tới).
3. Gói **Free** là đủ để chạy thử. Lưu ý: project miễn phí tự tạm dừng sau 7 ngày không ai dùng; trước buổi học vào Dashboard bấm **Restore** nếu thấy project đang dừng.

## 2. Cho phép đăng nhập ẩn danh

Học viên không cần tài khoản: mỗi trình duyệt tự nhận một danh tính ẩn danh.

1. **Authentication → Sign In / Providers** (hoặc **Authentication → Settings**), bật **Allow anonymous sign-ins**, bấm Save.
2. **Authentication → Rate Limits**: dòng **Anonymous sign-ins** mặc định chỉ 30 lượt mỗi giờ cho một địa chỉ IP. Cả lớp dùng chung wifi VinUni nên sẽ chung một IP, hãy nâng lên **500**.

## 3. Tạo bảng và luật bảo mật

1. Mở **SQL Editor → New query**.
2. Dán toàn bộ nội dung file [`lop-hoc-lang.sql`](lop-hoc-lang.sql).
3. Bấm **Run**, rồi đặt **mật mã Key Coach** bằng một câu riêng (thay `key-2611` bằng mật mã bạn muốn):

   ```sql
   update lhl_config set v = 'key-2611' where k = 'key_code';
   ```
4. Bấm **Run**. Thấy "Success" là xong. Chạy lại file nhiều lần cũng không mất dữ liệu.

Chạy lại cả file SQL về sau **không** làm mất mật mã đã đặt. Muốn đổi mật mã thì chạy lại câu `update` ở trên với mật mã mới.

## 4. Lấy 2 giá trị kết nối

Vào **Project Settings → Data API** (hoặc **API Keys**), chép:

- **Project URL**, dạng `https://abcdxyz.supabase.co`
- **Publishable key** (`sb_publishable_…`) hoặc **anon public key** (chuỗi dài bắt đầu bằng `eyJ…`)

Gửi hai giá trị này để dán vào `SB_URL` và `SB_KEY` ở đầu đoạn mã trong `index.html`, hoặc tự dán rồi commit. Hai giá trị này công khai được, quyền truy cập nằm trong các hàm SQL ở bước 3.

**Không** gửi hay dán `service_role` / `secret key` vào trang.

## 5. Chạy thử

1. Mở https://sangdaden.github.io/lop-hoc-online/, chọn **Key Coach**, nhập **tên phòng học** (1 chữ cái + 3 số, ví dụ `H201`), chọn **buổi** (ví dụ Ngày 02 · Sáng; buổi quyết định nội dung ngày lab) và mật mã Key Coach, bấm Tiếp.
2. Mở ngăn **Cả lớp** (biểu tượng cột), mục **Phòng** có **mã vào lớp** (4 số, cho học viên), **mã Lab Coach** (4 số) và link mời. Mã vào lớp cũng hiện trên màn hình lớn trong phòng.
3. Đọc mã vào lớp cho cả lớp. Key Coach đã đặt sẵn tên phòng và buổi; học viên chỉ chọn vai Học viên rồi nhập đúng mã là vào thẳng lớp đó, không cần gõ gì thêm. Lab Coach nhập mã Lab Coach là vào thẳng lớp. Mã không bao giờ trùng giữa các lớp đang mở, nên không ai vào nhầm lớp khác. Gửi link mời thì mã được điền sẵn.
4. Hết buổi bấm **Đóng phòng**. Buổi sau Key Coach mở lại cùng tên phòng: trang mở **buổi mới** với mã vào lớp và mã Lab Coach mới, người và đăng ký demo của buổi trước được xóa (điểm cộng vẫn giữ).
5. Phòng đang mở mà Key Coach khác mở cùng tên phòng thì người đó nhận quyền dẫn, dữ liệu giữ nguyên.

**Báo lỗi "Could not find the function … in the schema cache"?** Nghĩa là Supabase chưa có hàm mới. Chạy lại toàn bộ file SQL mới nhất (bấm Run, thấy Success), đợi vài giây rồi tải lại trang game.

**Đã chạy file SQL bản cũ?** Chạy lại toàn bộ file mới một lần (dữ liệu không mất), mật mã Key Coach đã đặt vẫn giữ nguyên.

## Cách hoạt động (tóm tắt)

- Mọi bảng bật RLS và không có policy nào, nên trình duyệt không đọc hay ghi thẳng vào bảng. Trình duyệt chỉ gọi các hàm `lhl_*`, mỗi hàm tự kiểm vai và phòng còn mở.
- Học viên chỉ sửa được bản ghi của mình. Chỉ Key Coach đổi phase, mở/đóng demo, đổi sĩ số và kiểu bàn, đóng phòng. Chỉ coach xác nhận điểm cộng và đánh dấu "đang tới xem". Điểm cộng chỉ chính học viên đó và coach đọc được.
- Một ghế chỉ một người (chặn ngay trong cơ sở dữ liệu). Ai mất kết nối quá 60 giây được tính là đã rời phòng và nhả ghế. Vào lại bằng cùng trình duyệt thì giữ nguyên tiến độ.
- Mỗi máy hỏi máy chủ khoảng 2,5 giây một lần và chỉ nhận phần thay đổi, nên không cần kết nối realtime (gói miễn phí giới hạn 200 kết nối realtime). Thử trên máy với 250 người giả lập: khoảng 100 lượt hỏi mỗi giây, mỗi lượt dưới 10 ms.
- Dữ liệu lưu: tên hiển thị, ngoại hình, ghế, phase/mục đã tick, giơ tay, đã nộp hay chưa, đăng ký demo, lý do điểm cộng. Không lưu link repo, nội dung prompt hay email.

## Chiếu màn hình ở góc demo

- Không cần chạy lại SQL. Người đang được mời và người đang đứng ở chỗ đứng demo đi chung gói trạng thái của Key Coach.
- Hai máy bắt tay qua kênh **Realtime broadcast** của Supabase (kênh `lhl-stage-<phòng>`). Realtime bật sẵn ở mọi project, không phải làm gì. Chỉ Key Coach, người đang chiếu và người đang xem mở kênh này, nên lớp 250 người cũng chỉ dùng khoảng 10 kết nối realtime.
- Hình đi thẳng từ máy người chiếu tới từng người xem (WebRTC), không qua Supabase, nên không tốn dung lượng Supabase. Tối đa 8 người xem trực tiếp một lúc (`STAGE_MAX` trong index.html), luôn chừa 1 chỗ cho Key Coach.
- Mạng trường hoặc công ty chặn UDP thì người xem thấy "Không kết nối được tới máy người trình bày". Khi đó cần máy chủ TURN: tạo tài khoản ở một dịch vụ TURN (ví dụ Metered hoặc Cloudflare), rồi thêm một dòng vào `STAGE_ICE` trong index.html dạng `{urls:"turn:…",username:"…",credential:"…"}`.
