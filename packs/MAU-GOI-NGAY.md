# Gói bài lab theo ngày

Mỗi ngày lab là một file `packs/dayNN.json` (ví dụ `packs/day03.json`). Khi trang mở, game đọc file này. Ngày nào chưa có file thì game dùng **khung lab chung**: vẫn đủ 8 phase, 2 giờ nghỉ, chữ chung chung, để Key Coach mở lớp được.

Ví dụ đầy đủ: [day02.json](day02.json) (bài Ngày 02 Khóa 5, có cả bản dịch `en`). [mau-day02.json](mau-day02.json) là bản cũ, giữ để tham khảo.

## Thêm một ngày mới

1. Chép `mau-day02.json` thành `dayNN.json`, đổi `so` thành `"NN"`.
2. Sửa tiêu đề, link đề bài, các phase, mục tự kiểm, thẻ thuật ngữ.
3. Mở `lich.json`, điền ngày học (dạng `2026-11-10`). Game tự biết ngày nào đã qua, hôm nay, sắp tới.
4. Đẩy lên nhánh `gh-pages`. Không cần sửa `index.html`, không cần chạy SQL.

## Các trường

| Trường | Bắt buộc | Ý nghĩa |
|---|---|---|
| `so` | có | Số ngày, 2 chữ số: `"03"` |
| `tieuDe` | có | Tên ngày, hiện trên màn lớn và Sổ lab |
| `muc` | không | Một dòng tóm tắt đầu ra |
| `nguon` | không | Link đề bài (repo). Hiện thành nút "Đề bài Ngày NN" trong Sổ lab |
| `mau` | không | Link bài mẫu: `[["Tên", "https://..."], ...]` |
| `bang` | không | 4 dòng viết trên bảng trắng (dòng đầu là tiêu đề) |
| `vai` | không | Vai trong nhóm. Mặc định: Điều phối, Workflow, Research, Viết |
| `nop` | không | Thư mục hoặc file phải có trong repo nộp bài. Tên không có `.` hay `/` thì hiện thêm `/` ở cuối (thư mục) |
| `repo` | không | Chữ trên ô dán link khi nộp bài. Mặc định: "Link repo cá nhân (DayNN-MãHV-HọTên)" |
| `the` | không | Thẻ thuật ngữ: `[["Từ", "Giải thích ngắn"], ...]` |
| `onTap` | không | Thẻ "Ôn nhanh" ở phòng tự học: `[["Câu hỏi", "Đáp án"], ...]`. Mỗi lượt lấy ngẫu nhiên 5 thẻ. Không có thì dùng `the` |
| `truocBuoi` | không | Việc cần làm trước buổi này (cài công cụ, đọc trước...). Hiện ở phòng tự học dưới mục "Chuẩn bị Ngày NN" khi ngày này là buổi kế tiếp. Không có thì dùng danh sách chung |
| `phases` | có | Danh sách phase theo thứ tự, kể cả giờ nghỉ |
| `en` | không | Bản dịch tiếng Anh cho chữ của ngày này: `{"chữ tiếng Việt": "English"}`. Khớp nguyên câu trước, rồi khớp từng cụm. Thiếu thì chữ hiện tiếng Việt |

Mỗi phase:

| Trường | Ý nghĩa |
|---|---|
| `ten`, `ngan` | Tên đầy đủ và tên ngắn (hiện trên dải phase) |
| `phut` | Số phút |
| `cheDo` | `canhan` · `nhom` · `calop` · `nghi` (giờ nghỉ) |
| `ai` | `duoc` · `truoc` (tự làm trước, AI sau) · `phanbien` (AI chỉ để phản biện) · `khong` |
| `tuKiem` | Các mục học viên tự tick khi bấm "Xong bước" |
| `pitch` | `true` nếu phase có que nói để pitch |
| `moDemo` | `true` nếu phase mở đăng ký demo |
| `demo` | `"nhom"` hoặc `"canhan"`: kiểu demo gợi ý |
| `nopBai` | `true` ở phase nhắc nộp link repo |
| `link` | Link riêng cho phase (hiện trong Sổ lab khi tới phase đó) |

File hỏng hoặc thiếu `phases` thì game bỏ qua và dùng khung chung, lớp vẫn chạy.
