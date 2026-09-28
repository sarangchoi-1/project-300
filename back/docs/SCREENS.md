# 화면 흐름도 (Screens)

`260922` 안건 문서를 화면 단위로 정리한 흐름도입니다. 총 **32개 화면**, 7개 영역.

권한 게이트는 마름모(◇)로 표시했습니다. 색은 단계입니다.

- 🟩 **Phase 1 (MVP)** — 인증, 명단, 조 모임, 주보
- 🟨 **Phase 2** — 예배 출석, 시각화, 캘린더, 새가족 모임
- ⬜ **Phase 3** — 게시판, 앨범, PDF 내보내기, 방문자 관리

단계 구분은 제안입니다. 팀 논의로 조정하세요.

관련 문서: [백엔드 아키텍처](./ARCHITECTURE.md) · [팀 설명용](./TEAM_WALKTHROUGH.ko.md) · [Flutter 연동](./FLUTTER_AUTH_INTEGRATION.md)

---

## 0. 전체 화면 맵

네비게이션 바 후보가 스펙에는 8개(홈·명단·앨범·캘린더·주보·조모임·게시판·마이페이지)인데,
iOS/Android 하단 탭은 현실적으로 5개가 한계입니다. 아래는 **5탭 + 더보기** 안입니다.

```mermaid
flowchart TB
  Nav["하단 네비게이션"]

  Nav --> H["홈"]
  Nav --> L["명단"]
  Nav --> G["조 모임"]
  Nav --> B["주보"]
  Nav --> M["더보기"]

  M --> CAL["캘린더"]
  M --> ALB["앨범"]
  M --> BRD["게시판"]
  M --> MY["마이페이지"]

  H --> H1["오늘의 말씀"]
  H --> H2["인스타 / 유튜브"]
  H --> H3["이번 주 캘린더 요약"]
  H --> H4["주보 바로가기"]

  L --> L0["전체 · 조별 · 검색"]
  L0 --> L5["개인 프로필 상세"]
  L --> L1["필터 · 시각화"]
  L --> L2["예배 출석체크 · 총무"]
  L --> L3["상태 변경 · 교역자·임원"]
  L --> L4["방문자 명단 · 임원·교역자"]

  G --> G1["출석체크 (리더)"]
  G --> G2["GQS 본문 · 노트"]
  G --> G3["기도제목"]
  G --> G4["새가족 모임"]

  B --> B1["지난 주보"]
  B --> B2["주보 편집 (서기)"]

  BRD --> BR1["사진·글 게시판"]
  BRD --> BR2["기도제목 게시판"]

  classDef p1 fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef p2 fill:#fef9c3,stroke:#ca8a04,color:#713f12
  classDef p3 fill:#f1f5f9,stroke:#94a3b8,color:#334155
  classDef nav fill:#e0e7ff,stroke:#4f46e5,color:#312e81

  class Nav,M nav
  class H,L,G,B,H1,H4,L0,L5,G1,G2,G3,B1,B2 p1
  class CAL,L2,L3,G4,H3 p2
  class ALB,BRD,MY,BR1,BR2,L4,H2 p3
```

---

## 1. 인증 (Phase 1 — 완료)

백엔드는 이미 배포되어 있습니다. Flutter 화면만 남았습니다.

```mermaid
flowchart TD
  Start(["앱 실행"]) --> Sess{"저장된 세션<br/>있음?"}

  Sess -->|"없음"| Login["로그인 화면"]
  Sess -->|"있음"| Fetch["프로필 조회<br/>profiles select"]

  Login --> Cred{"이메일 / 비번<br/>일치?"}
  Cred -->|"불일치"| Retry["오류 표시 · 재시도"]
  Retry --> Cred
  Cred -->|"일치"| Fetch

  Login --> SignupBtn["회원가입"]
  SignupBtn --> SU["이메일 · 비번 · 이름 입력"]
  SU --> SUOK{"가입 성공?"}
  SUOK -->|"중복 이메일"| SUErr["오류 표시"]
  SUErr --> SU
  SUOK -->|"성공"| Auto["프로필 자동 생성<br/>member · pending"]
  Auto --> Wait

  Login --> Reset["비밀번호 재설정"]
  Reset --> Mail{"등록된<br/>이메일?"}
  Mail -->|"아니오"| MailErr["오류 표시"]
  MailErr --> Reset
  Mail -->|"예"| Sent["재설정 메일 발송"]
  Sent --> Login

  Fetch --> Status{"approval_status"}
  Status -->|"pending"| Wait["승인 대기 화면<br/>빈 목록이 정상"]
  Status -->|"rejected"| Denied["접근 거절 화면"]
  Status -->|"approved"| Stage{"member_stage"}

  Wait -.->|"관리자 승인 후 재진입"| Fetch

  Stage -->|"새가족"| HomeNF["홈 · 새가족 뷰<br/>조 모임 탭 숨김"]
  Stage -->|"일반"| Home["홈"]

  classDef p1 fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef gate fill:#fff7ed,stroke:#ea580c,color:#7c2d12
  class Start,Login,Fetch,Retry,SU,SignupBtn,SUErr,Auto,Reset,Sent,MailErr,Wait,Denied,Home,HomeNF p1
  class Sess,Cred,SUOK,Mail,Status,Stage gate
```

> `member_stage`(새가족 / 일반)는 **아직 스키마에 없습니다.** 스펙의 "새가족은 조 모임
> 아직 안 보이게" 요구사항을 위해 추가해야 합니다. [ARCHITECTURE.md](./ARCHITECTURE.md) 참고.

---

## 2. 홈 · 주보

주보는 링크 연결이 아니라 **앱 안에서 새로 만드는 것**으로 결정됨. 편집은 서기만.

```mermaid
flowchart TD
  Home["홈 화면"] --> Word["오늘의 말씀"]
  Home --> Social["인스타 · 유튜브 임베드"]
  Home --> CalSum["이번 주 캘린더"]
  Home --> ToB["주보 바로가기"]

  Home --> HEdit{"교역자 · 임원?"}
  HEdit -->|"예"| HomeEdit["홈 콘텐츠 편집<br/>말씀 · 링크"]

  ToB --> Bul["주보 화면"]
  Bul --> S1["예배 순서"]
  Bul --> S2["예배 위원"]
  Bul --> S3["광고"]
  Bul --> S4["교회 안내"]
  Bul --> Past["지난 주보 목록"]
  Past --> PastView["지난 주보 보기"]

  Bul --> BGate{"서기?"}
  BGate -->|"아니오"| ReadOnly["읽기 전용"]
  BGate -->|"예"| Edit["주보 편집 페이지"]
  Edit --> EditS["순서 · 위원 · 광고 · 안내 수정"]
  EditS --> Save["저장 → DB 반영"]
  Save --> Pub{"발행?"}
  Pub -->|"임시저장"| Draft["draft 상태<br/>서기만 보임"]
  Pub -->|"발행"| Live["published 상태<br/>전체 공개"]
  Draft --> Edit
  Live --> Bul

  Bul --> PDF["PDF 내보내기"]

  classDef p1 fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef p2 fill:#fef9c3,stroke:#ca8a04,color:#713f12
  classDef p3 fill:#f1f5f9,stroke:#94a3b8,color:#334155
  classDef gate fill:#fff7ed,stroke:#ea580c,color:#7c2d12
  class Home,Word,ToB,Bul,S1,S2,S3,S4,Past,PastView,ReadOnly,Edit,EditS,Save,Draft,Live p1
  class CalSum,HomeEdit p2
  class Social,PDF p3
  class HEdit,BGate,Pub gate
```

---

## 3. 조 모임 (스펙의 핵심 플로우)

스펙 원문 그대로: 조 모임 페이지 → 리더가 출석 체크 → 모임 시작 → GQS 본문 + 노트 →
모임 → 기도제목 → 모임 완료.

```mermaid
flowchart TD
  Entry["조 모임 페이지"] --> NF{"새가족?"}
  NF -->|"예"| Hidden["탭 자체가 안 보임<br/>새가족 모임으로"]
  NF -->|"아니오"| Role{"이 조의 리더?"}

  Role -->|"조원"| MemView["본문 · 내 노트 · 기도제목<br/>읽기 + 내 것만 작성"]
  Role -->|"리더"| Check["출석체크 화면<br/>조 명단 표시"]

  Check --> Tap["명단에서 참석자 체크"]
  Tap --> StartBtn["모임 시작 버튼"]
  StartBtn --> Meet["GQS 본문 주소 + 노트 화면"]

  Meet --> Note["노트 작성"]
  Note --> NoteSave["개인별 저장<br/>각자 자기 노트"]
  NoteSave --> Pray["기도제목 화면"]

  Pray --> Acc["누적 · 일자별로 쌓임"]
  Acc --> VisSel{"공개 범위"}
  VisSel -->|"전체공개"| V1["청년부 전체"]
  VisSel -->|"조원 공개"| V2["같은 조만"]
  VisSel -->|"리더 공개"| V3["교역자 · 리더만"]
  VisSel -->|"비공개"| V4["작성자만"]

  V1 --> Done["모임 완료"]
  V2 --> Done
  V3 --> Done
  V4 --> Done

  Done --> Stats["출결 현황 반영<br/>명단 시각화로"]

  MemView --> Pray

  classDef p1 fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef p2 fill:#fef9c3,stroke:#ca8a04,color:#713f12
  classDef gate fill:#fff7ed,stroke:#ea580c,color:#7c2d12
  class Entry,Hidden,MemView,Check,Tap,StartBtn,Meet,Note,NoteSave,Pray,Acc,V1,V2,V3,V4,Done p1
  class Stats p2
  class NF,Role,VisSel gate
```

**필요한 DB 3개** — 출결 현황, 노트(개인별), 기도제목. 기도제목의 4단계 공개 범위가
지금까지 만든 것 중 가장 까다로운 RLS입니다.

---

## 4. 새가족 모임 (Phase 2)

```mermaid
flowchart TD
  Entry["새가족 모임 페이지"] --> Who{"권한"}
  Who -->|"그 외"| NoAccess["접근 불가"]
  Who -->|"새가족"| NFView["내 교육 진행도<br/>내 기도제목"]
  Who -->|"새가족 리더 · 교역자"| Lead["명단 · 출석 화면"]

  Lead --> Chk["명단에서 참석 체크"]
  Chk --> Missing{"명단에<br/>없는 사람?"}
  Missing -->|"있음"| Kakao["카톡으로 별도 전달<br/>앱 외부 처리"]
  Missing -->|"없음"| Edu
  Kakao --> Edu["교육 진행도 입력"]

  Edu --> C1["새 생활의 시작 — 6과 중 n과"]
  Edu --> C2["질문 있어요 — 4과 중 n과"]

  C1 --> PrayW["기도제목 작성 — 리더가"]
  C2 --> PrayW
  PrayW --> Scope["공개 범위 고정<br/>새가족 리더 + 교역자만"]
  Scope --> Fin["완료"]

  classDef p2 fill:#fef9c3,stroke:#ca8a04,color:#713f12
  classDef gate fill:#fff7ed,stroke:#ea580c,color:#7c2d12
  classDef ext fill:#fee2e2,stroke:#dc2626,color:#7f1d1d
  class Entry,NFView,Lead,Chk,Edu,C1,C2,PrayW,Scope,Fin,NoAccess p2
  class Who,Missing gate
  class Kakao ext
```

> 새가족 기도제목은 "새가족 리더 + 교역자만"이라 조 모임 기도제목의 4단계와 **다른
> 5번째 범위**입니다. 같은 테이블에 범위 하나를 더할지, 테이블을 분리할지 결정 필요.

---

## 5. 명단 (Phase 1 — 앱의 중심 화면)

> ### ⚠️ 지금 배포된 DB로는 이 화면이 **동작하지 않습니다**
>
> `profiles`의 읽기 정책은 딱 두 개입니다. `profiles_select_own`(내 행만)과
> `profiles_select_admin`(관리자는 전체). 그래서 **일반 조원이 명단을 열면 자기 혼자
> 나옵니다.** 리더도 마찬가지로 자기 행만 보입니다.
>
> 명단이 앱의 중심이라면 `profiles`에 "승인된 사용자는 승인된 사용자를 볼 수 있다"는
> 정책이 새로 필요합니다. 이건 Backend 1 작업이고, 아래 9번의 1번 결정입니다.
> 범위를 정하기 전까지 Flutter에서 명단 화면을 붙여도 빈 화면이 나옵니다.

```mermaid
flowchart TD
  Tab["명단 탭"] --> G0{"is_approved()?"}
  G0 -->|"아니오"| Wait["승인 대기 화면"]
  G0 -->|"예"| Which{"어느 명단"}

  Which --> All["청년부 전체 명단"]
  Which --> Mine["내 조 명단"]

  All --> Mode{"보기 방식"}
  Mode --> M1["가나다순 전체"]
  Mode --> M2["조별 묶어보기"]
  Mode --> M3["이름 검색"]
  Mode --> M4["필터 적용"]

  M1 --> Card
  M2 --> Card
  M3 --> Card
  M4 --> Card
  Mine --> Card["명단 카드<br/>사진 · 이름 · 조 · 직분 배지"]

  Card --> Count["상단 요약<br/>전체 n명 · 조당 n명"]
  Card --> Tap["개인 프로필 상세"]

  Tap --> P1["기본 공개<br/>이름 · 사진 · 조 · 직분"]
  Tap --> PG1{"리더 이상?"}
  PG1 -->|"예"| P2["연락처"]
  Tap --> PG2{"본인 · 담당 리더<br/>· 교역자 · 임원?"}
  PG2 -->|"예"| P3["출석 기록<br/>예배 · 조 모임"]
  Tap --> PG3{"교역자 · 임원?"}
  PG3 -->|"예"| P4["상태 변경 페이지"]

  P4 --> E1["승인 · 거절"]
  P4 --> E2["역할 변경"]
  P4 --> E3["직분 부여 · 회수"]
  P4 --> E4["조 배정 · 이동"]
  P4 --> E5["속성 태그 수정"]

  Card --> MG{"총무?"}
  MG -->|"예"| AttBtn["출석체크 하기 버튼<br/>6번으로"]

  Card --> VG{"임원 · 교역자?"}
  VG -->|"예"| Vis["방문자 명단"]
  Vis --> VisAdd["방문자 입력 창"]

  classDef p1 fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef p2 fill:#fef9c3,stroke:#ca8a04,color:#713f12
  classDef p3 fill:#f1f5f9,stroke:#94a3b8,color:#334155
  classDef gate fill:#fff7ed,stroke:#ea580c,color:#7c2d12
  class Tab,Wait,All,Mine,M1,M2,M3,Card,Tap,P1,P4,E1,E2,E3,E4 p1
  class M4,Count,P2,P3,E5,AttBtn p2
  class Vis,VisAdd p3
  class G0,Which,Mode,PG1,PG2,PG3,MG,VG gate
```

### 명단에서 무엇이 누구에게 보이나

이게 명단 설계의 핵심입니다. 한 사람의 프로필이 통째로 공개되는 게 아니라
**항목별로 공개 범위가 다릅니다.**

| 항목 | 승인된 전체 | 담당 리더 | 교역자 · 임원 |
|---|---|---|---|
| 이름 · 프로필 사진 | ✅ | ✅ | ✅ |
| 소속 조 | ✅ | ✅ | ✅ |
| 직분 배지 | ✅ | ✅ | ✅ |
| 속성 태그 (학사생 · 군인 등) | 논의 필요 | ✅ | ✅ |
| 연락처 | ❌ | ✅ | ✅ |
| 출석 기록 | 본인만 | 자기 조원 | ✅ |
| 승인 상태 · 역할 | ❌ | ❌ | ✅ |

항목별로 다르다는 건 RLS만으로는 부족하고 **컬럼 단위 권한**이나 공개 항목만 담은
**뷰**가 필요하다는 뜻입니다. `profiles`를 통째로 열면 연락처와 승인 상태까지 딸려
나갑니다. [ARCHITECTURE.md](./ARCHITECTURE.md)의 2번 결정과 같은 문제입니다.

---

## 6. 예배 출석 · 시각화 (Phase 2)

`출석체크 하기` 버튼은 **총무에게만** 보입니다.

```mermaid
flowchart TD
  List["명단 화면"] --> MGate{"총무?"}
  MGate -->|"아니오"| NoBtn["버튼 안 보임"]
  MGate -->|"예"| MenuBtn["메뉴바 → 출석체크 하기"]
  MenuBtn --> Mode["화면 상태 전환<br/>각 사람 클릭 가능"]
  Mode --> Part{"예배 회차"}
  Part --> P1["1부"]
  Part --> P2["2부"]
  P1 --> Doing["출석 진행"]
  P2 --> Doing
  Doing --> SaveA["저장"]

  List --> Filter["필터"]
  Filter --> FS["저장된 속성<br/>학사생 · 형제/자매 · 또래<br/>군인 · 해외체류<br/>예배사역팀 · 예배스탭<br/>리더 · 새가족리더 · 임원 · 교역자"]
  Filter --> FD["계산되는 값<br/>몇 주 이상 결석<br/>대예배 1·2부 출석자"]

  SaveA --> Viz["시각화"]
  FS --> Viz
  FD --> Viz

  Viz --> VZ1["예배 출석 line chart<br/>x 시간 · y 인원"]
  Viz --> VZ2["조 모임 출석 line chart<br/>전체"]
  Viz --> VZ3["예배 출석 대비<br/>조 모임 출석률 %"]
  Viz --> VZ4["오늘 몇 명 · 조당 몇 명"]

  Viz --> VGate{"통계 열람 범위<br/>결정 필요"}
  VGate --> Export["PDF 내보내기"]

  classDef p1 fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef p2 fill:#fef9c3,stroke:#ca8a04,color:#713f12
  classDef p3 fill:#f1f5f9,stroke:#94a3b8,color:#334155
  classDef gate fill:#fff7ed,stroke:#ea580c,color:#7c2d12
  class List,Filter,FS,NoBtn p1
  class FD,Viz,VZ1,VZ2,VZ3,VZ4,MenuBtn,Mode,Doing,SaveA,Part,P1,P2 p2
  class Export p3
  class MGate,VGate gate
```

---

## 7. 게시판 · 앨범 · 마이페이지 (Phase 3)

```mermaid
flowchart TD
  Board["게시판"] --> B1["사진 · 글 게시판"]
  Board --> B2["기도제목 게시판"]

  B1 --> Post["게시글 상세"]
  B2 --> Post
  Post --> Like["좋아요"]
  Post --> Cmt["댓글"]
  Post --> Own{"작성자 본인?"}
  Own -->|"예"| EditP["수정 · 삭제"]
  Own -->|"아니오"| ReadP["읽기 전용"]

  Board --> New["글 작성"]
  New --> Upload["사진 업로드"]

  Album["앨범"] --> AL["앨범 목록"]
  AL --> Photos["사진 보기"]
  AL --> AGate{"임원 · 교역자?"}
  AGate -->|"예"| AUp["앨범 생성 · 사진 업로드"]

  My["마이페이지"] --> Prof["내 프로필"]
  Prof --> Avatar["프로필 사진 수정"]
  Prof --> MyName["표시 이름 수정"]
  My --> MyPray["내 기도제목"]
  My --> MyAtt["내 출석 기록"]
  My --> Out["로그아웃"]

  Cal["캘린더"] --> CView["월 · 주 보기"]
  CView --> CGate{"회장 · 교역자 · 임원?"}
  CGate -->|"예"| CEdit["일정 추가 · 수정 · 삭제"]

  classDef p1 fill:#dcfce7,stroke:#16a34a,color:#14532d
  classDef p2 fill:#fef9c3,stroke:#ca8a04,color:#713f12
  classDef p3 fill:#f1f5f9,stroke:#94a3b8,color:#334155
  classDef gate fill:#fff7ed,stroke:#ea580c,color:#7c2d12
  class MyName,Out,Prof,My p1
  class Cal,CView,CEdit p2
  class Board,B1,B2,Post,Like,Cmt,EditP,ReadP,New,Upload,Album,AL,Photos,AUp,Avatar,MyPray,MyAtt p3
  class Own,AGate,CGate gate
```

---

## 8. 화면별 권한 요약

| 화면 | 열람 | 편집 |
|---|---|---|
| 홈 | 승인된 전체 | 교역자 · 임원 |
| 주보 | 승인된 전체 | **서기** |
| 지난 주보 | 승인된 전체 | 서기 |
| 청년부 명단 | **정책 추가 필요** — 현재는 본인 행만 | 교역자 · 임원 |
| 내 조 명단 | 조원 + 담당 리더 | 교역자 · 임원 |
| 개인 프로필 상세 | 항목별로 다름 — 5번 표 참고 | 본인 · 교역자 · 임원 |
| 예배 출석체크 | **총무** | **총무** |
| 방문자 명단 | **임원 · 교역자** | 임원 · 교역자 |
| 상태 변경 | 교역자 · 임원 | 교역자 · 임원 |
| 시각화 · 통계 | 범위 논의 필요 | — |
| 조 모임 | 조원 + 리더, **새가족 제외** | 해당 조 리더 |
| 조모임 출석체크 | 해당 조 리더 | 해당 조 리더 |
| 노트 | 본인 것만 | 본인 |
| 기도제목 | 공개 범위에 따라 4단계 | 작성자 |
| 새가족 모임 | 새가족 · 새가족리더 · 교역자 | 새가족 리더 |
| 새가족 기도제목 | 새가족리더 · 교역자 | 새가족 리더 |
| 캘린더 | 승인된 전체 | **회장** · 교역자 · 임원 |
| 게시판 | 승인된 전체 | 작성자 본인 |
| 앨범 | 승인된 전체 | 임원 · 교역자 |
| 마이페이지 | 본인 | 본인 |

---

## 9. 결정이 필요한 것들

1. **🔴 명단 열람 범위 — 가장 급합니다.** 지금 정책으로는 일반 조원이 명단을 열면
   자기 혼자 나옵니다. 세 가지 안 중 하나를 골라야 Flutter가 명단 화면을 시작할 수
   있습니다.
   - (a) 승인된 사람은 승인된 사람 전체를 본다 — 교회 명단이니 자연스럽고 구현이 가장 단순
   - (b) 같은 조 + 리더만 본다 — 가장 보수적이지만 "청년부 명단" 화면이 성립 안 됨
   - (c) 이름·사진·조까지는 전체 공개, 연락처·출석은 리더 이상 — 5번 표대로. 가장
     현실적이지만 컬럼 단위 권한이나 뷰가 필요해서 구현이 제일 큼
2. **공개 항목을 어디까지.** 1번에서 (c)를 고르면 `profiles`를 그대로 열 수 없고
   공개 컬럼만 담은 뷰를 따로 만들어야 합니다.
3. **네비게이션 8개 → 5개.** 위 맵은 홈·명단·조모임·주보·더보기 안입니다.
4. **"이 앱은 새가족 친화적이지 않다"** — 스펙에 적힌 본인 메모입니다. 새가족이 첫
   실행에서 보는 화면을 정해야 1번 플로우가 확정됩니다. 목사님 논의 필요.
5. **시각화를 누구까지 보여줄지.** 출석률 통계는 민감할 수 있습니다. 전체 공개인지,
   리더 이상인지.
6. **새가족 기도제목 범위** — 4단계에 하나 더할지, 테이블 분리할지.
7. **예배 1부 / 2부** 구분을 출석에 남길지. 필터 목록에 "대예배[1,2부] 출석자"가
   있어서 회차 구분이 필요해 보입니다. 6번 다이어그램에는 회차 분기를 넣어뒀습니다.
8. **방문자가 나중에 정회원이 되는 경로.** 방문자 레코드를 `profiles`로 승격시킬지,
   별도로 둘지.
