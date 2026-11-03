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
3. Ở dòng cuối file, đổi `doi-mat-ma-nay` thành **mật mã Key Coach** bạn muốn (ví dụ giữ `key-2611` như bản mô phỏng).
4. Bấm **Run**. Thấy "Success" là xong. Chạy lại file nhiều lần cũng không mất dữ liệu.

Muốn đổi mật mã Key Coach sau này, chạy riêng dòng cuối với mật mã mới.

## 4. Lấy 2 giá trị kết nối

Vào **Project Settings → Data API** (hoặc **API Keys**), chép:

- **Project URL**, dạng `https://abcdxyz.supabase.co`
- **Publishable key** (`sb_publishable_…`) hoặc **anon public key** (chuỗi dài bắt đầu bằng `eyJ…`)

Gửi hai giá trị này để dán vào `SB_URL` và `SB_KEY` ở đầu đoạn mã trong `index.html`, hoặc tự dán rồi commit. Hai giá trị này công khai được, quyền truy cập nằm trong các hàm SQL ở bước 3.

**Không** gửi hay dán `service_role` / `secret key` vào trang.

## 5. Chạy thử

1. Mở https://sangdaden.github.io/lop-hoc-online/, chọn **Key Coach**, nhập mật mã, để trống ô mã phòng, bấm Tiếp. Trang tạo phòng mới.
2. Mở ngăn **Cả lớp** (biểu tượng cột), mục **Phòng** có mã phòng, link mời và mã Lab Coach.
3. Gửi link cho học viên. Lab Coach dùng cùng link, chọn vai Lab Coach và nhập mã Lab Coach.
4. Hết buổi bấm **Đóng phòng**. Lần sau Key Coach nhập lại mã cũ để mở lại, hoặc để trống để tạo phòng mới.

## Cách hoạt động (tóm tắt)

- Mọi bảng bật RLS và không có policy nào, nên trình duyệt không đọc hay ghi thẳng vào bảng. Trình duyệt chỉ gọi các hàm `lhl_*`, mỗi hàm tự kiểm vai và phòng còn mở.
- Học viên chỉ sửa được bản ghi của mình. Chỉ Key Coach đổi phase, mở/đóng demo, đổi sĩ số và kiểu bàn, đóng phòng. Chỉ coach xác nhận điểm cộng và đánh dấu "đang tới xem". Điểm cộng chỉ chính học viên đó và coach đọc được.
- Một ghế chỉ một người (chặn ngay trong cơ sở dữ liệu). Ai mất kết nối quá 60 giây được tính là đã rời phòng và nhả ghế. Vào lại bằng cùng trình duyệt thì giữ nguyên tiến độ.
- Mỗi máy hỏi máy chủ khoảng 2,5 giây một lần và chỉ nhận phần thay đổi, nên không cần kết nối realtime (gói miễn phí giới hạn 200 kết nối realtime). Thử trên máy với 250 người giả lập: khoảng 100 lượt hỏi mỗi giây, mỗi lượt dưới 10 ms.
- Dữ liệu lưu: tên hiển thị, ngoại hình, ghế, phase/mục đã tick, giơ tay, đã nộp hay chưa, đăng ký demo, lý do điểm cộng. Không lưu link repo, nội dung prompt hay email.
