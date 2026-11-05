-- Lớp Học Lặng · phòng thật trên Supabase
-- Chạy toàn bộ file này một lần trong Supabase Dashboard → SQL Editor → New query → Run.
-- Sau đó đặt mật mã Key Coach (dòng cuối file, đổi 'doi-mat-ma-nay').
--
-- Mô hình bảo mật: mọi bảng bật RLS và KHÔNG có policy nào, nên trình duyệt không đọc/ghi thẳng được bảng.
-- Trình duyệt chỉ gọi các hàm lhl_* bên dưới; mỗi hàm tự kiểm vai (học viên / Lab Coach / Key Coach) và phòng còn mở.

create extension if not exists pgcrypto with schema extensions;

create table if not exists lhl_config (k text primary key, v text not null);
create table if not exists lhl_key_auth (uid uuid primary key, at timestamptz not null default now());
create table if not exists lhl_rooms (
  code text primary key,
  key_uid uuid not null,
  open boolean not null default true,
  title text,
  lab text not null,
  pass text not null default '',
  state jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
-- Tên phòng theo phòng học thật: 1 chữ cái + 3 số (ví dụ H201). Mỗi buổi có mã vào lớp 4 số riêng, không trùng giữa các lớp đang mở.
alter table lhl_rooms add column if not exists pass text not null default '';
alter table lhl_rooms drop constraint if exists lhl_rooms_code_check;
alter table lhl_rooms drop constraint if exists lhl_rooms_code_fmt;
alter table lhl_rooms add constraint lhl_rooms_code_fmt check (code ~ '^[A-Z][0-9]{3}$') not valid;

create table if not exists lhl_members (
  code text not null references lhl_rooms(code) on delete cascade,
  uid uuid not null,
  name text not null check (char_length(name) between 1 and 24),
  role text not null check (role in ('hv','lab','key')),
  look jsonb,
  seat int not null default -1,
  step int not null default 0,
  chk int not null default 0,
  hand boolean not null default false,
  hand_at bigint not null default 0,
  nop boolean not null default false,
  grp_role text not null default '',
  zone int not null default 0,
  bow_n int not null default 0,
  x real, z real,
  help jsonb,
  help_done int not null default 0,
  help_n int not null default 0,
  help_wait real not null default 0,
  online boolean not null default true,
  joined bigint not null,
  upd bigint not null,
  seen bigint not null,
  primary key (code, uid)
);
-- Một ghế chỉ một người: chặn ngay trong cơ sở dữ liệu
create unique index if not exists lhl_members_seat on lhl_members(code, seat) where seat >= 0;
create index if not exists lhl_members_upd on lhl_members(code, upd);
-- Key Coach quản lý người: tạm khóa thao tác, khóa tên (sau khi Key Coach đổi tên), danh sách người bị mời ra trong buổi.
alter table lhl_members add column if not exists locked boolean not null default false;
alter table lhl_members add column if not exists fixname boolean not null default false;
create table if not exists lhl_ban (code text not null references lhl_rooms(code) on delete cascade, uid uuid not null, name text, role text, at bigint not null, primary key (code, uid));
create table if not exists lhl_demo (code text references lhl_rooms(code) on delete cascade, grp int, at bigint not null, by_uid uuid not null, primary key (code, grp));
create table if not exists lhl_pit (code text references lhl_rooms(code) on delete cascade, grp int, at int not null, primary key (code, grp));
create table if not exists lhl_bonus (
  id bigint generated always as identity primary key,
  code text not null references lhl_rooms(code) on delete cascade,
  uid uuid not null,
  ly text not null check (char_length(ly) between 5 and 140),
  st text not null default 'cho' check (st in ('cho','ok','bo')),
  at bigint not null
);
create index if not exists lhl_bonus_code on lhl_bonus(code, st);
create table if not exists lhl_esc (id bigint generated always as identity primary key, code text not null references lhl_rooms(code) on delete cascade, k int not null, by_name text, at bigint not null);
-- Vòng 3: giơ tay kèm loại kẹt (H5), vỗ tay khi demo (D1), nhật ký giơ tay cho báo cáo buổi (C2)
alter table lhl_members add column if not exists hand_k text not null default '';
alter table lhl_members add column if not exists clap_n int not null default 0;
-- Phòng tự học (C1): giờ kết thúc phiên tập trung (ms), > now thì đèn bàn sáng vàng
alter table lhl_members add column if not exists focus bigint not null default 0;
-- Phòng tự học có chủ (05/11): T001 Thư viện đêm, T002 Quán cà phê, T003 Nhà kính, T004 Giếng trời. Mỗi kiểu chỉ một phòng đang mở.
alter table lhl_rooms add column if not exists owner uuid;
alter table lhl_rooms add column if not exists empty_at bigint;
create table if not exists lhl_hlog (id bigint generated always as identity primary key, code text not null references lhl_rooms(code) on delete cascade, uid uuid not null, k int not null default 0, hk text not null default '', up bigint not null, down bigint);
create index if not exists lhl_hlog_code on lhl_hlog(code, uid);

alter table lhl_config enable row level security;
alter table lhl_key_auth enable row level security;
alter table lhl_rooms enable row level security;
alter table lhl_members enable row level security;
alter table lhl_demo enable row level security;
alter table lhl_pit enable row level security;
alter table lhl_bonus enable row level security;
alter table lhl_esc enable row level security;
alter table lhl_ban enable row level security;
alter table lhl_hlog enable row level security;

create or replace function lhl_now() returns bigint language sql stable as $$ select (extract(epoch from clock_timestamp())*1000)::bigint $$;

-- vai của người gọi trong phòng (null nếu chưa vào hoặc đã bị Key Coach mời ra)
create or replace function lhl_role(p_code text) returns text language sql stable security definer set search_path = public as $$
  select m.role from lhl_members m where m.code = p_code and m.uid = auth.uid()
    and not exists (select 1 from lhl_ban b where b.code = p_code and b.uid = m.uid)
$$;
create or replace function lhl_need(p_code text, p_roles text[]) returns void language plpgsql stable security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'chua dang nhap'; end if;
  if not exists (select 1 from lhl_rooms where code = p_code and open) then raise exception 'phong da dong'; end if;
  if coalesce(lhl_role(p_code), '') <> all (p_roles) then raise exception 'khong du quyen'; end if;
end $$;

-- người gọi đang bị Key Coach tạm khóa thao tác?
create or replace function lhl_locked(p_code text) returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select locked from lhl_members where code = p_code and uid = auth.uid()), false)
$$;

-- Key Coach: nhập mật mã một lần trên mỗi trình duyệt
create or replace function lhl_key_login(p_pass text) returns boolean language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then return false; end if;
  if exists (select 1 from lhl_key_auth where uid = auth.uid()) then return true; end if;
  -- Mật mã vẫn là chữ mẫu: báo rõ để người quản trị đặt mật mã thật, thay vì báo "sai mật mã".
  if coalesce((select v from lhl_config where k = 'key_code'), 'doi-mat-ma-nay') = 'doi-mat-ma-nay' then raise exception 'chua dat mat ma key coach'; end if;
  if p_pass is not null and p_pass = (select v from lhl_config where k = 'key_code') then
    insert into lhl_key_auth(uid) values (auth.uid()) on conflict do nothing; return true;
  end if;
  perform pg_sleep(0.5);
  return false;
end $$;

drop function if exists lhl_create_room(text);
-- Key Coach mở phòng theo tên phòng học (H201). Phòng đang đóng thì mở buổi mới: mã mới, xóa người và đăng ký demo của buổi trước.
-- Phòng đang mở do Key Coach khác giữ thì chuyển cho người vừa mở (đổi người dẫn giữa buổi), giữ nguyên dữ liệu.
create or replace function lhl_create_room(p_code text, p_title text) returns json language plpgsql security definer set search_path = public, extensions as $$
declare r lhl_rooms; v_lab text; v_pass text;
begin
  if not exists (select 1 from lhl_key_auth where uid = auth.uid()) then raise exception 'khong phai key coach'; end if;
  if p_code !~ '^[A-Z][0-9]{3}$' then raise exception 'ten phong khong dung'; end if;
  if p_code = 'T000' then raise exception 'T000 la phong tu hoc'; end if;
  -- Mã vào lớp và mã Lab Coach đều 4 số, không trùng với mã nào của lớp đang mở, vì người vào chỉ nhập mã.
  loop
    v_pass := lpad(((get_byte(gen_random_bytes(1),0)*256 + get_byte(gen_random_bytes(1),0)) % 9000 + 1000)::text, 4, '0');
    exit when not exists (select 1 from lhl_rooms where open and code <> p_code and v_pass in (pass, lab));
  end loop;
  loop
    v_lab := lpad(((get_byte(gen_random_bytes(1),0)*256 + get_byte(gen_random_bytes(1),0)) % 9000 + 1000)::text, 4, '0');
    exit when v_lab <> v_pass and not exists (select 1 from lhl_rooms where open and code <> p_code and v_lab in (pass, lab));
  end loop;
  if p_code in ('T001','T002','T003','T004') then raise exception 'T001-T004 la phong tu hoc'; end if;
  select * into r from lhl_rooms where code = p_code;
  if not found then
    insert into lhl_rooms(code, key_uid, title, lab, pass) values (p_code, auth.uid(), left(p_title, 60), v_lab, v_pass);
    return json_build_object('code', p_code, 'lab', v_lab, 'pass', v_pass, 'fresh', true);
  end if;
  if not r.open or r.pass = '' then
    delete from lhl_members where code = p_code;
    delete from lhl_demo where code = p_code;
    delete from lhl_pit where code = p_code;
    delete from lhl_esc where code = p_code;
    delete from lhl_ban where code = p_code;
    delete from lhl_hlog where code = p_code;
    update lhl_rooms set key_uid = auth.uid(), open = true, title = left(p_title, 60), lab = v_lab, pass = v_pass, state = '{}'::jsonb, created_at = now() where code = p_code;
    return json_build_object('code', p_code, 'lab', v_lab, 'pass', v_pass, 'fresh', true);
  end if;
  update lhl_rooms set key_uid = auth.uid() where code = p_code;
  return json_build_object('code', p_code, 'lab', r.lab, 'pass', r.pass, 'fresh', false);
end $$;

drop function if exists lhl_open_rooms();
-- Học viên nhập mã vào lớp (Lab Coach nhập mã Lab Coach) là ra đúng lớp đang mở.
create or replace function lhl_find(p_role text, p_pass text) returns text language sql stable security definer set search_path = public as $$
  select code from lhl_rooms
  where open and code <> 'T000' and created_at > now() - interval '18 hours'
    and case when p_role = 'lab' then lab = trim(p_pass) else pass = trim(p_pass) end
  order by created_at desc limit 1
$$;

-- Ai cũng hỏi được: phòng có tồn tại, còn mở không. Key Coach của phòng nhận thêm mã Lab Coach.
create or replace function lhl_room_info(p_code text) returns json language sql stable security definer set search_path = public as $$
  select json_build_object('open', open, 'mine', key_uid = auth.uid(), 'lab', case when key_uid = auth.uid() then lab end, 'pass', case when key_uid = auth.uid() then pass end)
  from lhl_rooms where code = p_code
$$;
create or replace function lhl_my_rooms() returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('code', code, 'open', open, 'title', title) order by created_at desc), '[]'::json)
  from (select * from lhl_rooms where key_uid = auth.uid() order by created_at desc limit 5) r
$$;
create or replace function lhl_open(p_code text, p_open boolean) returns void language plpgsql security definer set search_path = public as $$
begin
  update lhl_rooms set open = p_open where code = p_code and key_uid = auth.uid();
  if not found then raise exception 'khong du quyen'; end if;
end $$;

-- Vào phòng với một vai. Lab Coach phải có mã Lab Coach của phòng. Vào lại thì giữ tiến độ cũ.
create or replace function lhl_join(p_code text, p_role text, p_pass text, p_name text, p_look jsonb) returns json language plpgsql security definer set search_path = public as $$
declare r lhl_rooms; old lhl_members; t bigint := lhl_now();
begin
  if auth.uid() is null then return json_build_object('err', 'auth'); end if;
  select * into r from lhl_rooms where code = p_code;
  if not found then return json_build_object('err', 'none'); end if;
  if not r.open and r.key_uid <> auth.uid() then return json_build_object('err', 'closed'); end if;
  if p_role = 'key' and r.key_uid <> auth.uid() then return json_build_object('err', 'notkey'); end if;
  if p_role <> 'key' and exists (select 1 from lhl_ban where code = p_code and uid = auth.uid()) then return json_build_object('err', 'ban'); end if;
  if p_role = 'lab' and coalesce(p_pass, '') <> r.lab
     and not exists (select 1 from lhl_members where code = p_code and uid = auth.uid() and role = 'lab') then
    perform pg_sleep(0.5); return json_build_object('err', 'labpass');
  end if;
  if p_role = 'hv' and p_code <> 'T000' and r.owner is null and coalesce(p_pass, '') <> r.pass
     and not exists (select 1 from lhl_members where code = p_code and uid = auth.uid()) then
    perform pg_sleep(0.5); return json_build_object('err', 'pass');
  end if;
  if p_role not in ('hv','lab','key') then return json_build_object('err', 'role'); end if;
  if r.key_uid = auth.uid() and not r.open then update lhl_rooms set open = true where code = p_code; end if;
  select * into old from lhl_members where code = p_code and uid = auth.uid();
  if found then
    update lhl_members set name = case when old.fixname then old.name else left(p_name, 24) end, look = p_look, role = p_role, seat = -1, hand = false, help = null, online = true, upd = t, seen = t,
      step = case when old.role = p_role then old.step else 0 end, chk = case when old.role = p_role then old.chk else 0 end
    where code = p_code and uid = auth.uid();
  else
    insert into lhl_members(code, uid, name, role, look, joined, upd, seen) values (p_code, auth.uid(), left(p_name, 24), p_role, p_look, t, t, t);
  end if;
  -- Mỗi lớp chỉ một Key Coach: người vừa vào với vai Key Coach thay hẳn bản ghi Key Coach cũ (tab khác, máy khác, người dẫn trước).
  if p_role = 'key' then
    delete from lhl_members where code = p_code and role = 'key' and uid <> auth.uid();
  end if;
  return json_build_object('ok', true, 'old', case when old.uid is not null then row_to_json(old) end, 'lab', case when p_role = 'key' then r.lab end, 'pass', case when p_role = 'key' then r.pass end);
end $$;

-- Cập nhật bản ghi của chính mình (chỉ các trường cho phép)
create or replace function lhl_me(p_code text, p_patch jsonb) returns void language plpgsql security definer set search_path = public as $$
declare t bigint := lhl_now(); o lhl_members; st jsonb; v_k int;
begin
  perform lhl_need(p_code, array['hv','lab','key']);
  select * into o from lhl_members where code = p_code and uid = auth.uid();
  update lhl_members set
    name = case when fixname then name else coalesce(left(p_patch->>'name', 24), name) end,
    look = case when p_patch ? 'look' then p_patch->'look' else look end,
    step = coalesce((p_patch->>'step')::int, step),
    chk = coalesce((p_patch->>'chk')::int, chk),
    hand = case when locked then false else coalesce((p_patch->>'hand')::boolean, hand) end,
    hand_at = case when locked then hand_at when (p_patch->>'hand')::boolean then t when p_patch ? 'hand' then 0 else hand_at end,
    help = case when (p_patch->>'hand')::boolean is not null then null else help end,
    hand_k = case when locked then hand_k when p_patch ? 'handK' then left(coalesce(p_patch->>'handK', ''), 8) when p_patch ? 'hand' then '' else hand_k end,
    clap_n = coalesce((p_patch->>'clapN')::int, clap_n),
    focus = coalesce((p_patch->>'focus')::bigint, focus),
    nop = coalesce((p_patch->>'nop')::boolean, nop),
    grp_role = coalesce(left(p_patch->>'grpRole', 24), grp_role),
    zone = coalesce((p_patch->>'zone')::int, zone),
    bow_n = coalesce((p_patch->>'bowN')::int, bow_n),
    x = case when locked then x else coalesce((p_patch->>'x')::real, x) end, z = case when locked then z else coalesce((p_patch->>'z')::real, z) end,
    online = coalesce((p_patch->>'on')::boolean, online),
    upd = t, seen = t
  where code = p_code and uid = auth.uid();
  -- C2: ghi lượt giơ tay theo phase (phase Key Coach đang dẫn; phòng tự học thì phase của chính học viên)
  if found and not o.locked and p_patch ? 'hand' then
    if (p_patch->>'hand')::boolean and not o.hand then
      select state into st from lhl_rooms where code = p_code;
      v_k := case when st->>'mode' = 'tuhoc' then coalesce((p_patch->>'step')::int, o.step) else coalesce((st->>'guide')::int, 0) end;
      update lhl_hlog set down = t where code = p_code and uid = auth.uid() and down is null;
      insert into lhl_hlog(code, uid, k, hk, up) values (p_code, auth.uid(), v_k, left(coalesce(p_patch->>'handK', ''), 8), t);
    elsif not coalesce((p_patch->>'hand')::boolean, true) and o.hand then
      update lhl_hlog set down = t where code = p_code and uid = auth.uid() and down is null;
    end if;
  end if;
  -- Phòng tự học: mỗi phiên tập trung mới thêm 1 lá (Nhà kính) và cộng phút (đồng hồ cát Giếng trời). Đếm theo ngày giờ Việt Nam.
  if found and p_patch ? 'focus' and coalesce((p_patch->>'focus')::bigint, 0) > t and coalesce(o.focus, 0) <= t then
    update lhl_rooms set state = state || jsonb_build_object('fday', to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD'),
      'leaf', case when state->>'fday' = to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD') then coalesce((state->>'leaf')::int, 0) else 0 end + 1,
      'fmin', case when state->>'fday' = to_char(now() at time zone 'Asia/Ho_Chi_Minh', 'YYYY-MM-DD') then coalesce((state->>'fmin')::int, 0) else 0 end
        + greatest(1, least(120, (((p_patch->>'focus')::bigint - t + 30000) / 60000)::int)))
    where code = p_code and state->>'mode' = 'tuhoc';
  end if;
  if found and p_patch ? 'handK' and not (p_patch ? 'hand') then
    update lhl_hlog set hk = left(coalesce(p_patch->>'handK', ''), 8) where code = p_code and uid = auth.uid() and down is null;
  end if;
end $$;

-- Ngồi / rời ghế. Ghế của người đã rời phòng (mất kết nối > 60 giây) được giải phóng.
create or replace function lhl_seat(p_code text, p_seat int) returns boolean language plpgsql security definer set search_path = public as $$
declare t bigint := lhl_now();
begin
  perform lhl_need(p_code, array['hv']);
  if lhl_locked(p_code) then return false; end if;
  if p_seat >= 0 then
    update lhl_members set seat = -1, hand = false, online = false, upd = t
      where code = p_code and seat = p_seat and uid <> auth.uid() and (not online or seen < t - 60000);
  end if;
  begin
    update lhl_members set seat = p_seat, hand = false, help = null, upd = t, seen = t where code = p_code and uid = auth.uid();
  exception when unique_violation then return false;
  end;
  return true;
end $$;

-- Lab Coach / Key Coach đánh dấu đang tới xem (by) hoặc đã xem (seen). Không hạ tay hộ học viên.
create or replace function lhl_help(p_code text, p_uid uuid, p_help jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  perform lhl_need(p_code, array['lab','key']);
  update lhl_members set help = p_help, upd = lhl_now() where code = p_code and uid = p_uid and hand;
end $$;
create or replace function lhl_stat(p_code text, p_done int, p_n int, p_wait real) returns void language plpgsql security definer set search_path = public as $$
begin
  perform lhl_need(p_code, array['lab','key']);
  update lhl_members set help_done = p_done, help_n = p_n, help_wait = p_wait, upd = lhl_now() where code = p_code and uid = auth.uid();
end $$;

-- Trạng thái chung của phòng: chỉ Key Coach ghi
create or replace function lhl_state(p_code text, p_state jsonb) returns void language plpgsql security definer set search_path = public as $$
begin
  update lhl_rooms set state = p_state where code = p_code and key_uid = auth.uid() and open;
  if not found then raise exception 'khong du quyen'; end if;
  if (p_state->>'clearSeats')::boolean then update lhl_members set seat = -1, hand = false, help = null, upd = lhl_now() where code = p_code; end if;
end $$;

-- Đăng ký demo theo nhóm: chỉ khi Key Coach đang mở
create or replace function lhl_demo_set(p_code text, p_grp int, p_on boolean) returns boolean language plpgsql security definer set search_path = public as $$
begin
  perform lhl_need(p_code, array['hv','lab','key']);
  if lhl_locked(p_code) then return false; end if;
  if lhl_role(p_code) <> 'key' and not coalesce((select (state->>'demoOpen')::boolean from lhl_rooms where code = p_code), false) then return false; end if;
  if p_on then insert into lhl_demo(code, grp, at, by_uid) values (p_code, p_grp, lhl_now(), auth.uid()) on conflict do nothing;
  else delete from lhl_demo where code = p_code and grp = p_grp; end if;
  return true;
end $$;

create or replace function lhl_pit_set(p_code text, p_grp int, p_at int) returns void language plpgsql security definer set search_path = public as $$
begin
  perform lhl_need(p_code, array['hv','lab','key']);
  if lhl_locked(p_code) then return; end if;
  if p_at < 0 then delete from lhl_pit where code = p_code and (p_grp < 0 or grp = p_grp); return; end if;
  insert into lhl_pit(code, grp, at) values (p_code, p_grp, p_at) on conflict (code, grp) do update set at = excluded.at;
end $$;

-- Điểm cộng: học viên gửi / rút (khi chưa xác nhận); coach xác nhận hoặc bỏ qua
create or replace function lhl_bonus_add(p_code text, p_ly text) returns bigint language plpgsql security definer set search_path = public as $$
declare i bigint;
begin
  perform lhl_need(p_code, array['hv']);
  if lhl_locked(p_code) then raise exception 'dang bi khoa'; end if;
  insert into lhl_bonus(code, uid, ly, at) values (p_code, auth.uid(), left(p_ly, 140), lhl_now()) returning id into i; return i;
end $$;
create or replace function lhl_bonus_del(p_code text, p_id bigint) returns boolean language plpgsql security definer set search_path = public as $$
begin
  perform lhl_need(p_code, array['hv']);
  delete from lhl_bonus where id = p_id and code = p_code and uid = auth.uid() and st = 'cho'; return found;
end $$;
create or replace function lhl_bonus_set(p_code text, p_id bigint, p_st text) returns void language plpgsql security definer set search_path = public as $$
begin
  perform lhl_need(p_code, array['lab','key']);
  update lhl_bonus set st = p_st where id = p_id and code = p_code;
end $$;

-- Danh sách điểm cộng của buổi này để coach tải về (cả khi phòng đã đóng, để Key Coach lỡ quên vẫn tải được)
create or replace function lhl_bonus_list(p_code text) returns json language plpgsql stable security definer set search_path = public as $$
declare r lhl_rooms;
begin
  if auth.uid() is null then raise exception 'chua dang nhap'; end if;
  select * into r from lhl_rooms where code = p_code;
  if not found then raise exception 'khong co phong'; end if;
  if r.key_uid <> auth.uid() and coalesce(lhl_role(p_code), '') not in ('lab','key') then raise exception 'khong du quyen'; end if;
  return (select coalesce(json_agg(json_build_object('uid', b.uid, 'name', m.name, 'seat', m.seat, 'ly', b.ly, 'st', b.st, 'at', b.at) order by b.at), '[]'::json)
    from lhl_bonus b left join lhl_members m on m.code = b.code and m.uid = b.uid
    where b.code = p_code and b.at >= (extract(epoch from r.created_at)*1000)::bigint);
end $$;

-- Lab Coach báo Key Coach một phase kẹt nhiều
create or replace function lhl_esc_add(p_code text, p_k int, p_by text) returns void language plpgsql security definer set search_path = public as $$
begin
  perform lhl_need(p_code, array['lab']);
  insert into lhl_esc(code, k, by_name, at) values (p_code, p_k, left(p_by, 30), lhl_now());
end $$;

-- Key Coach quản lý một người trong lớp (học viên hoặc Lab Coach). Không ai khác trong lớp thấy việc này.
--   stand: cho đứng dậy, trả ghế · lock / unlock: tạm khóa thao tác · rename: đổi tên thành "Học viên N" và khóa tên
--   kick: mời ra khỏi lớp, không vào lại được buổi này · unban: cho vào lại
create or replace function lhl_mod(p_code text, p_uid uuid, p_act text) returns boolean language plpgsql security definer set search_path = public as $$
declare t bigint := lhl_now(); m lhl_members; n int;
begin
  if not exists (select 1 from lhl_rooms where code = p_code and key_uid = auth.uid()) then raise exception 'khong du quyen'; end if;
  if coalesce(lhl_role(p_code), '') <> 'key' then raise exception 'khong du quyen'; end if;
  if p_uid = auth.uid() then return false; end if;
  if p_act = 'unban' then delete from lhl_ban where code = p_code and uid = p_uid; return found; end if;
  select * into m from lhl_members where code = p_code and uid = p_uid;
  if not found or m.role = 'key' then return false; end if;
  if p_act = 'stand' then
    update lhl_members set seat = -1, hand = false, help = null, upd = t where code = p_code and uid = p_uid;
  elsif p_act in ('lock', 'unlock') then
    update lhl_members set locked = (p_act = 'lock'), hand = case when p_act = 'lock' then false else hand end, help = case when p_act = 'lock' then null else help end, upd = t where code = p_code and uid = p_uid;
  elsif p_act = 'rename' then
    if m.fixname then return true; end if;
    select count(*) + 1 into n from lhl_members where code = p_code and fixname;
    update lhl_members set name = case when m.role = 'lab' then 'Lab Coach ' else 'Học viên ' end || n, fixname = true, upd = t where code = p_code and uid = p_uid;
  elsif p_act = 'kick' then
    insert into lhl_ban(code, uid, name, role, at) values (p_code, p_uid, m.name, m.role, t) on conflict (code, uid) do update set at = excluded.at, name = excluded.name;
    delete from lhl_demo where code = p_code and by_uid = p_uid;
    delete from lhl_bonus where code = p_code and uid = p_uid and st = 'cho';
    update lhl_members set seat = -1, hand = false, help = null, online = false, upd = t where code = p_code and uid = p_uid;
  else
    return false;
  end if;
  return true;
end $$;

-- Key Coach đổi mã vào lớp giữa buổi (người bị mời ra vào lại bằng máy khác). Ai đang trong lớp vẫn ở lại.
create or replace function lhl_newpass(p_code text) returns text language plpgsql security definer set search_path = public, extensions as $$
declare v_pass text;
begin
  if not exists (select 1 from lhl_rooms where code = p_code and key_uid = auth.uid() and open) then raise exception 'khong du quyen'; end if;
  loop
    v_pass := lpad(((get_byte(gen_random_bytes(1),0)*256 + get_byte(gen_random_bytes(1),0)) % 9000 + 1000)::text, 4, '0');
    exit when not exists (select 1 from lhl_rooms where open and v_pass in (pass, lab));
  end loop;
  update lhl_rooms set pass = v_pass where code = p_code;
  return v_pass;
end $$;

-- Hỏi trạng thái phòng (mỗi ~2,5 giây). Chỉ trả người có thay đổi từ lần trước, nên rất nhẹ.
create or replace function lhl_poll(p_code text, p_since bigint, p_beat boolean) returns json language plpgsql security definer set search_path = public as $$
declare t bigint := lhl_now(); r lhl_rooms; me_role text; res json;
begin
  if auth.uid() is null then raise exception 'chua dang nhap'; end if;
  me_role := lhl_role(p_code);
  if me_role is null and exists (select 1 from lhl_ban where code = p_code and uid = auth.uid()) then raise exception 'bi moi ra'; end if;
  if me_role is null then raise exception 'chua vao phong'; end if;
  if p_beat and p_code in ('T001','T002','T003','T004') then perform lhl_self_tidy(p_code); end if;
  select * into r from lhl_rooms where code = p_code;
  if p_beat and r.open then
    update lhl_members set seen = t, online = true, upd = case when online then upd else t end where code = p_code and uid = auth.uid();
    -- người mất kết nối quá 60 giây: coi như đã rời phòng
    update lhl_members set online = false, seat = -1, hand = false, help = null, upd = t
      where code = p_code and online and seen < t - 60000;
  end if;
  select json_build_object(
    'now', t,
    'open', r.open,
    'state', r.state,
    'owner', r.owner,
    'title', r.title,
    'members', (select coalesce(json_agg(json_build_object(
        'uid', m.uid, 'name', m.name, 'role', m.role, 'look', m.look, 'seat', m.seat, 'step', m.step, 'chk', m.chk,
        'hand', m.hand, 'handAt', m.hand_at, 'nop', m.nop, 'grpRole', m.grp_role, 'zone', m.zone, 'bowN', m.bow_n,
        'x', m.x, 'z', m.z, 'help', m.help, 'on', m.online, 'at', m.joined,
        'hd', m.help_done, 'hn', m.help_n, 'hw', m.help_wait, 'lock', m.locked, 'fix', m.fixname, 'hk', m.hand_k, 'clapN', m.clap_n, 'focus', m.focus)), '[]'::json)
      from lhl_members m where m.code = p_code and m.upd >= p_since),
    'demo', (select coalesce(json_agg(grp order by at), '[]'::json) from lhl_demo where code = p_code),
    'pit', (select coalesce(json_object_agg(grp, at), '{}'::json) from lhl_pit where code = p_code),
    'bonus', case when me_role = 'hv'
      then (select coalesce(json_agg(json_build_object('id', id, 'ly', ly, 'st', st, 'at', at) order by at), '[]'::json) from lhl_bonus where code = p_code and uid = auth.uid())
      else (select coalesce(json_agg(json_build_object('id', b.id, 'uid', b.uid, 'ly', b.ly, 'st', b.st, 'at', b.at, 'name', m.name, 'seat', m.seat) order by b.at), '[]'::json)
            from lhl_bonus b left join lhl_members m on m.code = b.code and m.uid = b.uid where b.code = p_code and b.st = 'cho') end,
    'bonOk', case when me_role <> 'hv' then (select coalesce(json_object_agg(uid, n), '{}'::json) from (select uid, count(*) n from lhl_bonus where code = p_code and st = 'ok' group by uid) q) end,
    'ban', case when me_role = 'key' then (select coalesce(json_agg(json_build_object('uid', uid, 'name', name, 'role', role, 'at', at) order by at desc), '[]'::json) from lhl_ban where code = p_code) end,
    'esc', case when me_role = 'key' then (select coalesce(json_agg(json_build_object('k', k, 'by', by_name, 'at', at) order by at), '[]'::json) from lhl_esc where code = p_code and at >= p_since) end
  ) into res;
  return res;
end $$;

-- C2: báo cáo buổi cho coach: lượt giơ tay theo phase + tiến độ học viên. Không có tên trong báo cáo theo phase.
create or replace function lhl_report(p_code text) returns json language plpgsql stable security definer set search_path = public as $$
begin
  perform lhl_need(p_code, array['key','lab']);
  return json_build_object(
    'now', lhl_now(),
    'hands', (select coalesce(json_agg(json_build_object('k', h.k, 'hk', h.hk, 'up', h.up,
        'down', coalesce(h.down, case when coalesce(m.hand, false) then null else m.upd end)) order by h.up), '[]'::json)
      from lhl_hlog h left join lhl_members m on m.code = h.code and m.uid = h.uid where h.code = p_code),
    'steps', (select coalesce(json_agg(json_build_object('step', step, 'chk', chk)), '[]'::json) from lhl_members where code = p_code and role = 'hv'));
end $$;

-- T1: phòng tự học T000 luôn mở, không cần Key Coach, không cần mã. Ai vào cũng tự đi phase của mình.
-- Người không vào lại quá 12 giờ được xóa khỏi phòng để danh sách không phình ra.
create or replace function lhl_self_room() returns text language plpgsql security definer set search_path = public, extensions as $$
declare t bigint := lhl_now();
begin
  if auth.uid() is null then raise exception 'chua dang nhap'; end if;
  insert into lhl_rooms(code, key_uid, open, title, lab, pass, state)
    values ('T000', '00000000-0000-0000-0000-000000000000', true, 'Phòng tự học', encode(gen_random_bytes(8), 'hex'), '',
      '{"N":50,"type":"island","mode":"tuhoc","day":"","guide":0,"brk":false,"endAt":0,"re":0,"call":0}'::jsonb)
    on conflict (code) do update set open = true;
  update lhl_rooms set state = state || '{"decor":{"theme":"A","light":"auto","sound":"auto","sign":true,"floor":true}}'::jsonb where code = 'T000' and not (state ? 'decor');
  delete from lhl_members where code = 'T000' and seen < t - 12 * 3600 * 1000;
  delete from lhl_hlog where code = 'T000' and up < t - 12 * 3600 * 1000;
  return 'T000';
end $$;


-- ---------- Phòng tự học có chủ (05/11) ----------
-- Mỗi kiểu một phòng: T001 A Thư viện đêm, T002 B Quán cà phê, T003 C Nhà kính, T004 D Giếng trời. Ai cũng vào tự do, không mã.
-- Người mở phòng là chủ: chỉ chủ đổi decor (ánh sáng, âm nền, biển cửa, đèn sàn). Chủ không đuổi ai, không khóa ghế.
create or replace function lhl_self_code(p_theme text) returns text language sql immutable as $$
  select case p_theme when 'A' then 'T001' when 'B' then 'T002' when 'C' then 'T003' when 'D' then 'T004' end $$;
create or replace function lhl_self_type(p_theme text) returns text language sql immutable as $$
  select case p_theme when 'B' then 'cafe' when 'C' then 'garden' when 'D' then 'ring' else 'island' end $$;

-- Dọn phòng: không ai trong phòng quá 30 phút thì đóng. Chủ mất kết nối quá 60 giây thì chuyển cho người vào sớm nhất đang ở phòng.
create or replace function lhl_self_tidy(p_code text) returns void language plpgsql security definer set search_path = public as $$
declare t bigint := lhl_now(); r lhl_rooms; nxt uuid; n int;
begin
  select * into r from lhl_rooms where code = p_code for update;
  if not found or r.owner is null or not r.open then return; end if;
  select count(*) into n from lhl_members where code = p_code and online and seen >= t - 60000;
  if n = 0 then
    if r.empty_at is null then update lhl_rooms set empty_at = t where code = p_code;
    elsif r.empty_at < t - 30 * 60000 then update lhl_rooms set open = false where code = p_code; delete from lhl_members where code = p_code; delete from lhl_hlog where code = p_code;
    end if;
    return;
  end if;
  if r.empty_at is not null then update lhl_rooms set empty_at = null where code = p_code; end if;
  if not exists (select 1 from lhl_members where code = p_code and uid = r.owner and seen >= t - 60000) then
    select uid into nxt from lhl_members where code = p_code and online and seen >= t - 60000 order by joined limit 1;
    if nxt is not null then update lhl_rooms set owner = nxt where code = p_code; end if;
  end if;
end $$;

-- Danh sách phòng tự học đang mở (phòng chung T000 đứng đầu, rồi theo số người).
create or replace function lhl_self_list() returns json language plpgsql security definer set search_path = public, extensions as $$
declare t bigint := lhl_now(); c text;
begin
  if auth.uid() is null then raise exception 'chua dang nhap'; end if;
  perform lhl_self_room();
  for c in select code from lhl_rooms where code in ('T001','T002','T003','T004') and open loop perform lhl_self_tidy(c); end loop;
  return (select coalesce(json_agg(x order by x.pub desc, x.n desc, x.code), '[]'::json) from (
    select r.code, r.title, coalesce(r.state->'decor'->>'theme', 'A') as theme, (r.code = 'T000') as pub,
      (select m.name from lhl_members m where m.code = r.code and m.uid = r.owner) as oname,
      coalesce(r.owner = auth.uid(), false) as mine,
      (select count(*) from lhl_members m where m.code = r.code and m.online and m.seen >= t - 60000) as n
    from lhl_rooms r where r.open and r.code in ('T000','T001','T002','T003','T004')) x);
end $$;

-- Mở phòng một kiểu. Kiểu đó đang có phòng mở thì trả mã phòng đó (vào chung), không mở thêm.
create or replace function lhl_self_create(p_title text, p_theme text) returns json language plpgsql security definer set search_path = public, extensions as $$
declare v_code text := lhl_self_code(p_theme); r lhl_rooms;
begin
  if auth.uid() is null then raise exception 'chua dang nhap'; end if;
  if v_code is null then raise exception 'kieu phong khong dung'; end if;
  perform lhl_self_tidy(v_code);
  select * into r from lhl_rooms where code = v_code for update;
  if found and r.open then return json_build_object('code', v_code, 'fresh', false); end if;
  delete from lhl_rooms where code = v_code;
  insert into lhl_rooms(code, key_uid, open, title, lab, pass, owner, state)
    values (v_code, '00000000-0000-0000-0000-000000000000', true, left(coalesce(nullif(trim(p_title), ''), 'Phòng tự học'), 40), encode(gen_random_bytes(8), 'hex'), '', auth.uid(),
      jsonb_build_object('N', 30, 'type', lhl_self_type(p_theme), 'mode', 'tuhoc', 'day', '', 'guide', 0, 'brk', false, 'endAt', 0, 're', 0, 'call', 0,
        'decor', jsonb_build_object('theme', p_theme, 'light', 'auto', 'sound', 'auto', 'sign', true, 'floor', true)));
  return json_build_object('code', v_code, 'fresh', true);
end $$;

-- Chủ phòng đổi decor. Chỉ nhận các giá trị có sẵn.
create or replace function lhl_self_decor(p_code text, p_decor jsonb) returns void language plpgsql security definer set search_path = public as $$
declare r lhl_rooms; d jsonb;
begin
  select * into r from lhl_rooms where code = p_code;
  if not found or r.owner is distinct from auth.uid() then raise exception 'khong phai chu phong'; end if;
  d := coalesce(r.state->'decor', '{}'::jsonb);
  if p_decor->>'light' in ('auto','sang','chieu','dem') then d := d || jsonb_build_object('light', p_decor->>'light'); end if;
  if p_decor->>'sound' in ('auto','mua','nang','thu') then d := d || jsonb_build_object('sound', p_decor->>'sound'); end if;
  if p_decor ? 'sign' then d := d || jsonb_build_object('sign', coalesce((p_decor->>'sign')::boolean, true)); end if;
  if p_decor ? 'floor' then d := d || jsonb_build_object('floor', coalesce((p_decor->>'floor')::boolean, true)); end if;
  if p_decor ? 'title' and coalesce(trim(p_decor->>'title'), '') <> '' then update lhl_rooms set title = left(trim(p_decor->>'title'), 40) where code = p_code; end if;
  update lhl_rooms set state = state || jsonb_build_object('decor', d) where code = p_code;
end $$;

-- Chủ nhường phòng cho một người đang ở trong phòng (p_uid null: người vào sớm nhất).
create or replace function lhl_self_give(p_code text, p_uid uuid) returns boolean language plpgsql security definer set search_path = public as $$
declare t bigint := lhl_now(); r lhl_rooms; nxt uuid;
begin
  select * into r from lhl_rooms where code = p_code for update;
  if not found or r.owner is distinct from auth.uid() then return false; end if;
  select uid into nxt from lhl_members where code = p_code and uid <> auth.uid() and online and seen >= t - 60000 and (p_uid is null or uid = p_uid) order by joined limit 1;
  if nxt is null then return false; end if;
  update lhl_rooms set owner = nxt where code = p_code;
  return true;
end $$;

-- Chỉ người đã đăng nhập (kể cả ẩn danh) mới gọi được các hàm
do $$ declare f record; begin
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace where n.nspname = 'public' and p.proname like 'lhl\_%' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;

-- Báo API nạp lại danh sách hàm ngay (tránh lỗi "Could not find the function ... in the schema cache").
notify pgrst, 'reload schema';

-- Mật mã Key Coach. Chạy lại cả file KHÔNG đổi mật mã đã đặt.
-- Lần đầu, hoặc khi muốn đổi mật mã: chạy riêng câu dưới (bỏ dấu -- ở đầu), thay mat-ma-cua-ban bằng mật mã thật.
--   update lhl_config set v = 'mat-ma-cua-ban' where k = 'key_code';
insert into lhl_config(k, v) values ('key_code', 'doi-mat-ma-nay') on conflict (k) do nothing;
