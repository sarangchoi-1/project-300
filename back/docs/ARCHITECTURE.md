# 백엔드 아키텍처 (Architecture)

`260922` 안건을 백엔드 구조로 옮긴 설계도입니다. [화면 흐름도](./SCREENS.md)와 짝입니다.

현재 배포된 것은 **인증 기반(3개 테이블)** 뿐이고, 스펙을 다 채우려면 **테이블 약 18개**와
**역할 모델 확장**이 필요합니다. 아래에서 `[배포됨]` / `[추가 필요]`로 구분했습니다.

관련 문서: [핸드오프](./BACKEND1_HANDOFF.md) · [Backend 2 계약](./BACKEND2_RLS_CONTRACT.md) · [팀 설명용](./TEAM_WALKTHROUGH.ko.md)

---

## 1. 시스템 구조

앱 서버가 없습니다. Flutter가 Supabase와 직접 통신하고, 권한은 전부 DB 안의 RLS가 담당합니다.

```mermaid
flowchart TB
  subgraph CLIENT["Flutter 앱"]
    UI["화면 27개"]
    SDK["supabase_flutter"]
    UI --> SDK
  end

  subgraph EDGE["Supabase 엣지 — mrcc_app · ap-northeast-2"]
    AUTH["Auth<br/>이메일·비번 · JWT 발급"]
    REST["PostgREST<br/>테이블을 HTTP API로"]
    STOR["Storage<br/>프로필사진 · 주보PDF<br/>앨범 · 게시판 이미지"]
    RT["Realtime<br/>선택 — 출석 실시간 반영"]
  end

  subgraph DB["PostgreSQL 17.6"]
    subgraph B1["Backend 1 — 신원 · 조직 · 권한"]
      T1["profiles · groups · group_members"]
      T2["직분 · 속성 태그"]
      FN["권한 헬퍼 함수"]
      T1 --> FN
      T2 --> FN
    end

    subgraph B2["Backend 2 — 기능 테이블"]
      F1["주보"]
      F2["출석 · 노트 · 기도제목"]
      F3["새가족 · 교육 진행"]
      F4["캘린더 · 게시판 · 앨범 · 방문자"]
    end

    RLS["RLS 정책<br/>모든 테이블"]
  end

  SDK -->|"HTTPS + anon key"| AUTH
  SDK -->|"HTTPS + JWT"| REST
  SDK -->|"HTTPS + JWT"| STOR
  SDK -.->|"WebSocket"| RT

  AUTH -->|"auth.users<br/>트리거로 profiles 자동 생성"| T1
  REST --> RLS
  STOR --> RLS
  RT --> RLS
  RLS --> B1
  RLS --> B2

  FN ==>|"Backend 2는 이 함수만 호출<br/>직접 join 금지"| B2

  classDef done fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef todo fill:#fef9c3,stroke:#ca8a04,color:#713f12
  classDef sec fill:#fee2e2,stroke:#dc2626,color:#7f1d1d
  classDef edge fill:#e0e7ff,stroke:#4f46e5,color:#312e81

  class T1,FN done
  class T2,F1,F2,F3,F4,UI,SDK todo
  class RLS sec
  class AUTH,REST,STOR,RT edge
```

굵은 화살표가 두 백엔드 사이의 **유일한 접점**입니다. Backend 2는 `profiles`나
`group_members`에 직접 join하지 않고 헬퍼 함수만 호출합니다. 그래야 나중에 조직 구조가
바뀌어도 기능 정책이 안 깨집니다.

---

## 2. 역할 모델 — 3층 분리

스펙에 등장하는 역할이 9개입니다. 그런데 성질이 서로 다릅니다.

- **총무**는 "예배 출석체크"라는 행동 하나를 하는 한 사람 → 직분
- **새가족**은 시간이 지나면 벗어나는 상태 → 단계
- **학사생 · 군인 · 해외체류 · 또래**는 역할이 아니라 사람의 속성 → 태그

이걸 `app_role` 하나에 다 넣으면 한 사람이 회장이면서 임원일 수가 없고, 필터용 속성은
들어갈 자리가 없습니다. 그래서 세 층으로 나눕니다.

```mermaid
flowchart LR
  subgraph L1["1층 · app_role — 접근 등급 · 배포됨"]
    R1["member — 일반 조원"]
    R2["leader — 조 · 새가족 리더"]
    R3["admin — 교역자 · 임원"]
  end

  subgraph L2["2층 · 직분 position — 무엇을 할 수 있나 · 추가 필요"]
    P1["pastor 교역자"]
    P2["officer 임원"]
    P3["president 회장"]
    P4["manager 총무"]
    P5["secretary 서기"]
    P6["newfamily_leader 새가족리더"]
  end

  subgraph L3["3층 · 속성 tag — 필터링용 · 추가 필요"]
    G1["성별 형제·자매"]
    G2["또래 기수·출생년"]
    G3["학사생"]
    G4["군인 · 해외체류"]
    G5["예배사역팀 · 예배스탭"]
  end

  subgraph L4["단계 stage · 추가 필요"]
    S1["newfamily 새가족"]
    S2["regular 일반"]
  end

  PROF["profiles"] --> L1
  PROF --> L4
  PROF -->|"N:M"| L2
  PROF -->|"N:M"| L3

  classDef done fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef todo fill:#fef9c3,stroke:#ca8a04,color:#713f12
  class R1,R2,R3 done
  class P1,P2,P3,P4,P5,P6,G1,G2,G3,G4,G5,S1,S2 todo
```

직분과 속성은 **N:M**입니다. 한 사람이 회장이면서 임원일 수 있고, 학사생이면서
예배사역팀일 수 있습니다. 조 리더는 예외로 이미 `group_members.role`에 있으니 직분에
중복하지 않습니다 — 어느 조의 리더인지가 같이 필요하기 때문입니다.

`몇 주 이상 결석`과 `대예배 1·2부 출석자`는 **저장하지 않습니다.** 출석 데이터에서
계산되는 값이라 뷰나 쿼리로 뽑습니다. 태그로 만들면 반드시 실제와 어긋납니다.

---

## 3. 데이터 모델

### 3-1. 신원 · 조직 · 권한 (Backend 1)

```mermaid
erDiagram
  auth_users ||--|| profiles : "1:1 cascade"
  profiles ||--o{ group_members : "소속"
  groups ||--o{ group_members : "구성원"
  profiles ||--o{ profile_positions : "직분"
  positions ||--o{ profile_positions : "부여"
  profiles ||--o{ profile_tags : "속성"
  tags ||--o{ profile_tags : "부여"

  profiles {
    uuid id PK
    text display_name
    app_role role
    approval_status approval_status
    member_stage stage "추가"
    text avatar_url "추가"
    int cohort_year "추가 · 또래"
    gender gender "추가 · 형제자매"
  }
  groups {
    uuid id PK
    text name
    bool is_active
  }
  group_members {
    uuid id PK
    uuid group_id FK
    uuid user_id FK
    group_role role
    bool is_active
  }
  positions {
    church_position code PK "추가"
  }
  profile_positions {
    uuid profile_id FK "추가"
    church_position position FK
    bool is_active
  }
  tags {
    uuid id PK "추가"
    text name
  }
  profile_tags {
    uuid profile_id FK "추가"
    uuid tag_id FK
  }
```

### 3-2. 기능 테이블 (Backend 2)

```mermaid
erDiagram
  bulletins ||--o{ bulletin_sections : "구성"
  services ||--o{ worship_attendance : "예배 출석"
  profiles ||--o{ worship_attendance : "대상자"
  groups ||--o{ group_meetings : "조 모임"
  group_meetings ||--o{ meeting_attendance : "출결"
  group_meetings ||--o{ meeting_notes : "노트"
  group_meetings ||--o{ prayer_requests : "기도제목"
  profiles ||--o{ meeting_notes : "개인별"
  profiles ||--o{ prayer_requests : "작성자"
  newfamily_meetings ||--o{ newfamily_attendance : "출결"
  curriculums ||--o{ curriculum_progress : "과정"
  profiles ||--o{ curriculum_progress : "진행도"
  posts ||--o{ post_comments : "댓글"
  posts ||--o{ post_likes : "좋아요"
  posts ||--o{ post_images : "이미지"
  albums ||--o{ album_photos : "사진"

  bulletins {
    uuid id PK
    date service_date
    bulletin_status status "draft·published"
    uuid created_by FK
  }
  bulletin_sections {
    section_kind kind "순서·위원·광고·안내"
    int position
    text content
  }
  services {
    date service_date
    service_part part "1부·2부"
  }
  worship_attendance {
    bool present
    uuid checked_by FK "총무"
  }
  group_meetings {
    date meeting_date
    meeting_status status
    text gqs_passage
    text gqs_url
  }
  meeting_notes {
    uuid profile_id FK "개인별"
    text body
  }
  prayer_requests {
    prayer_visibility visibility "4단계"
    text body
    date created_on "일자별 누적"
  }
  curriculum_progress {
    int completed_lessons
  }
  visitors {
    text name
    text contact
    date visited_on
    uuid invited_by FK
  }
  calendar_events {
    text title
    timestamptz starts_at
    bool all_day
  }
  posts {
    board_kind board "사진글·기도제목"
    text title
    text body
  }
  albums {
    text title
    date event_date
  }
```

### 3-3. 테이블 목록과 단계

| 테이블 | 영역 | 담당 | 단계 |
|---|---|---|---|
| `profiles` `groups` `group_members` | 신원·조직 | B1 | **배포됨** |
| `positions` `profile_positions` | 직분 | B1 | 1 |
| `tags` `profile_tags` | 속성 | B1 | 1 |
| `bulletins` `bulletin_sections` | 주보 | B2 | 1 |
| `group_meetings` `meeting_attendance` | 조모임 출결 | B2 | 1 |
| `meeting_notes` | 노트 | B2 | 1 |
| `prayer_requests` | 기도제목 | B2 | 1 |
| `services` `worship_attendance` | 예배 출석 | B2 | 2 |
| `newfamily_meetings` `newfamily_attendance` | 새가족 | B2 | 2 |
| `curriculums` `curriculum_progress` | 교육 진행 | B2 | 2 |
| `calendar_events` | 캘린더 | B2 | 2 |
| `posts` `post_images` `post_likes` `post_comments` | 게시판 | B2 | 3 |
| `albums` `album_photos` | 앨범 | B2 | 3 |
| `visitors` | 방문자 | B2 | 3 |

---

## 4. 권한 헬퍼 함수

**행동 이름으로 만드는 것**이 핵심입니다. 스펙에 "캘린더 수정 권한: 회장 혹은
교역자/임원"처럼 여러 직분이 묶여 나오는데, `can_edit_calendar()`로 감싸두면 나중에
"부회장도 추가"가 함수 한 곳만 고치는 일이 됩니다. 직분 이름으로 만들면 정책을 전부
찾아 고쳐야 합니다.

```mermaid
flowchart TB
  subgraph EXIST["배포됨 — 7개"]
    E1["is_approved()"]
    E2["is_admin()"]
    E3["is_group_member(group_id)"]
    E4["is_group_leader(group_id)"]
    E5["is_group_leader_of_user(user_id)"]
    E6["active_group_id()"]
    E7["current_app_role()"]
  end

  subgraph BASE["추가 · 기반"]
    B01["has_position(position)"]
    B02["is_newfamily()"]
  end

  subgraph CAP["추가 · 행동 단위"]
    C1["can_edit_bulletin()<br/>서기"]
    C2["can_check_worship()<br/>총무"]
    C3["can_edit_calendar()<br/>회장·교역자·임원"]
    C4["can_manage_members()<br/>교역자·임원"]
    C5["can_view_visitors()<br/>임원·교역자"]
    C6["can_lead_newfamily()<br/>새가족리더·교역자"]
    C7["can_see_prayer(request_id)<br/>4단계 판정"]
  end

  B01 --> C1
  B01 --> C2
  B01 --> C3
  B01 --> C4
  B01 --> C5
  B01 --> C6
  E3 --> C7
  E4 --> C7

  CAP ==> USE["Backend 2 RLS 정책"]
  E1 ==> USE

  classDef done fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef todo fill:#fef9c3,stroke:#ca8a04,color:#713f12
  class E1,E2,E3,E4,E5,E6,E7 done
  class B01,B02,C1,C2,C3,C4,C5,C6,C7 todo
```

전부 기존과 같은 규칙으로 만듭니다 — `security definer`, `stable`,
`set search_path = ''`, `authenticated`와 `service_role`에만 grant.

### 가장 어려운 정책: 기도제목 4단계

```mermaid
flowchart TD
  Q["기도제목 한 건을<br/>내가 볼 수 있나?"] --> A{"is_approved()?"}
  A -->|"아니오"| NO["안 보임"]
  A -->|"예"| V{"visibility"}

  V -->|"public 전체공개"| YES["보임"]
  V -->|"group 조원공개"| G{"같은 조?"}
  V -->|"leaders 리더공개"| L{"교역자 또는<br/>그 조 리더?"}
  V -->|"private 비공개"| P{"작성자 본인?"}

  G -->|"예"| YES
  G -->|"아니오"| NO
  L -->|"예"| YES
  L -->|"아니오"| NO
  P -->|"예"| YES
  P -->|"아니오"| NO

  classDef gate fill:#fff7ed,stroke:#ea580c,color:#7c2d12
  classDef yes fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef no fill:#fee2e2,stroke:#dc2626,color:#7f1d1d
  class A,V,G,L,P gate
  class YES yes
  class NO no
```

작성자는 범위와 무관하게 항상 자기 글을 봅니다. 위 판정을 `can_see_prayer()` 하나로
감싸서 Backend 2가 `using (public.can_see_prayer(id))`만 쓰게 만드는 게 목표입니다.

---

## 5. Storage 버킷

| 버킷 | 용도 | 공개 | 업로드 권한 |
|---|---|---|---|
| `avatars` | 프로필 사진 | 승인된 사용자 | 본인만 |
| `bulletins` | 주보 PDF | 승인된 사용자 | 서기 |
| `album-photos` | 앨범 | 승인된 사용자 | 임원·교역자 |
| `post-images` | 게시판 이미지 | 승인된 사용자 | 작성자 |

Storage도 RLS가 걸립니다. 버킷을 public으로 만들면 URL을 아는 누구나 접근하므로,
전부 private으로 두고 정책 + signed URL로 처리합니다.

---

## 6. 구현 순서

```mermaid
flowchart LR
  S0["배포됨<br/>인증 기반"] --> S1["B1 · 역할 모델 확장<br/>직분 · 태그 · 단계"]
  S1 --> S2["B1 · 행동 단위 헬퍼"]
  S2 --> S3["B2 · Phase 1 테이블<br/>주보 · 조모임 · 기도제목"]
  S1 --> F1["Flutter · 인증 화면<br/>지금 바로 가능"]
  S3 --> S4["Phase 2<br/>예배출석 · 시각화 · 캘린더 · 새가족"]
  S4 --> S5["Phase 3<br/>게시판 · 앨범 · 방문자 · PDF"]

  classDef done fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef now fill:#fef9c3,stroke:#ca8a04,color:#713f12
  classDef later fill:#f1f5f9,stroke:#94a3b8,color:#334155
  class S0 done
  class S1,S2,F1 now
  class S3,S4,S5 later
```

**S1 · S2가 Backend 2를 막고 있습니다.** 총무·서기·회장이 스키마에 없으면 주보 편집
정책이나 예배 출석체크 정책을 쓸 수가 없습니다. 반면 Flutter 인증 화면은 지금 바로
시작할 수 있습니다 — 그 부분은 이미 클라우드에 배포되어 있습니다.

---

## 7. 결정이 필요한 것들

1. **직분 이름을 코드에서 영어로 쓸지 한글로 쓸지.** 위에서는 영어(`manager`,
   `secretary`)로 했습니다. 한글 enum도 PostgreSQL에서 되지만 쿼리가 번거로워집니다.
2. **총무·서기가 자동으로 admin인지.** 예배 출석체크는 전체 명단 쓰기가 필요한데,
   그러면 총무가 남의 역할도 바꿀 수 있게 됩니다. 분리하려면 컬럼 단위 정책이 필요합니다.
3. **새가족 기도제목**을 `prayer_visibility`에 5번째 값으로 넣을지, 테이블을 분리할지.
4. **또래를 기수로 볼지 출생년으로 볼지.** 필터 정확도가 달라집니다.
5. **시각화 데이터를 뷰로 만들지 클라이언트 집계로 할지.** 뷰가 빠르지만 뷰에도
   RLS 설계가 필요합니다.
6. **예배 1부/2부**를 `services`로 분리하는 게 맞는지 확인.
7. **방문자 → 정회원 승격 경로.**
