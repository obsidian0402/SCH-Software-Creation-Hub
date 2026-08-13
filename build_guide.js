const {
  Document, Packer, Paragraph, TextRun, HeadingLevel, AlignmentType,
  Table, TableRow, TableCell, WidthType, ShadingType, BorderStyle,
  TableOfContents, PageBreak, LevelFormat, convertInchesToTwip
} = require('docx');
const fs = require('fs');

const FONT = '맑은 고딕';
const W = 9000;

// ---------- helpers ----------
const P = (text, opts = {}) => new Paragraph({
  children: Array.isArray(text)
    ? text
    : [new TextRun({ text, font: FONT, size: opts.size || 20, bold: opts.bold, italics: opts.italics, color: opts.color })],
  spacing: { after: opts.after != null ? opts.after : 120, line: 300 },
  alignment: opts.align,
  indent: opts.indent,
  border: opts.border,
});

const H = (text, level) => new Paragraph({
  children: [new TextRun({ text, font: FONT, bold: true,
    size: level === HeadingLevel.HEADING_1 ? 30 : level === HeadingLevel.HEADING_2 ? 25 : 22 })],
  heading: level,
  spacing: { before: level === HeadingLevel.HEADING_1 ? 360 : 260, after: 140 },
});

const BULLET = (text, level = 0) => new Paragraph({
  children: [new TextRun({ text, font: FONT, size: 20 })],
  numbering: { reference: 'bul', level },
  spacing: { after: 60, line: 300 },
});

const NUM = (text) => new Paragraph({
  children: [new TextRun({ text, font: FONT, size: 20 })],
  numbering: { reference: 'num', level: 0 },
  spacing: { after: 60, line: 300 },
});

const CODE = (lines) => new Paragraph({
  children: lines.flatMap((l, i) => [
    new TextRun({ text: l, font: 'Consolas', size: 17, break: i === 0 ? 0 : 1 })
  ]),
  spacing: { before: 100, after: 160, line: 260 },
  shading: { type: ShadingType.CLEAR, fill: 'F4F4F4' },
  indent: { left: 200, right: 200 },
  border: {
    top: { style: BorderStyle.SINGLE, size: 4, color: 'DDDDDD' },
    bottom: { style: BorderStyle.SINGLE, size: 4, color: 'DDDDDD' },
    left: { style: BorderStyle.SINGLE, size: 4, color: 'DDDDDD' },
    right: { style: BorderStyle.SINGLE, size: 4, color: 'DDDDDD' },
  },
});

const NOTE = (label, text, fill) => new Table({
  width: { size: W, type: WidthType.DXA },
  columnWidths: [W],
  rows: [new TableRow({
    children: [new TableCell({
      width: { size: W, type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, fill: fill },
      margins: { top: 120, bottom: 120, left: 180, right: 180 },
      children: [
        new Paragraph({ children: [new TextRun({ text: label, font: FONT, size: 19, bold: true })], spacing: { after: 60 } }),
        new Paragraph({ children: [new TextRun({ text: text, font: FONT, size: 19 })], spacing: { after: 0 }, }),
      ],
    })],
  })],
});

function table(headers, rows, widths) {
  const total = widths.reduce((a, b) => a + b, 0);
  const cols = widths.map(w => Math.round(w / total * W));
  cols[cols.length - 1] = W - cols.slice(0, -1).reduce((a, b) => a + b, 0);

  const hdr = new TableRow({
    tableHeader: true,
    children: headers.map((h, i) => new TableCell({
      width: { size: cols[i], type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, fill: '2F5597' },
      margins: { top: 80, bottom: 80, left: 100, right: 100 },
      children: [new Paragraph({
        children: [new TextRun({ text: h, font: FONT, size: 18, bold: true, color: 'FFFFFF' })],
        spacing: { after: 0 },
      })],
    })),
  });

  const body = rows.map((r, ri) => new TableRow({
    children: r.map((c, i) => new TableCell({
      width: { size: cols[i], type: WidthType.DXA },
      shading: { type: ShadingType.CLEAR, fill: ri % 2 ? 'F2F5FA' : 'FFFFFF' },
      margins: { top: 70, bottom: 70, left: 100, right: 100 },
      children: String(c).split('\n').map((line, li) => new Paragraph({
        children: [new TextRun({ text: line, font: FONT, size: 18 })],
        spacing: { after: li === String(c).split('\n').length - 1 ? 0 : 40, line: 270 },
      })),
    })),
  }));

  return new Table({ width: { size: W, type: WidthType.DXA }, columnWidths: cols, rows: [hdr, ...body] });
}

const SP = (h = 120) => new Paragraph({ children: [], spacing: { after: h } });

// ---------- content ----------
const kids = [];

// Title page
kids.push(new Paragraph({ children: [], spacing: { after: 1800 } }));
kids.push(new Paragraph({
  children: [new TextRun({ text: '제어기 이슈관리 DB', font: FONT, size: 44, bold: true, color: '2F5597' })],
  alignment: AlignmentType.CENTER, spacing: { after: 160 },
}));
kids.push(new Paragraph({
  children: [new TextRun({ text: '구축 실행 가이드', font: FONT, size: 44, bold: true, color: '2F5597' })],
  alignment: AlignmentType.CENTER, spacing: { after: 400 },
}));
kids.push(new Paragraph({
  children: [new TextRun({ text: 'Implementation Execution Guide  v1.0', font: FONT, size: 22, color: '666666' })],
  alignment: AlignmentType.CENTER, spacing: { after: 1400 },
}));
kids.push(table(
  ['항목', '내용'],
  [
    ['문서 버전', 'v1.0'],
    ['작성일', '2026년 7월 30일'],
    ['선행 문서', 'SCH 제어기 이슈관리 DB 간이 요구사항서 v0.6'],
    ['대상 독자', '이슈관리 프로그램 개발 담당자'],
    ['문서 성격', '요구사항을 실제 구현 순서로 옮긴 실행 지침서'],
  ],
  [2, 6]
));
kids.push(new Paragraph({ children: [new PageBreak()] }));

// TOC
kids.push(H('목차', HeadingLevel.HEADING_1));
kids.push(new TableOfContents('목차', { hyperlink: true, headingStyleRange: '1-2' }));
kids.push(new Paragraph({ children: [new PageBreak()] }));

// 1
kids.push(H('1. 이 문서의 사용법', HeadingLevel.HEADING_1));
kids.push(P('본 가이드는 간이 요구사항서(v0.6)에 정의된 요구사항을 실제 구축 순서로 재배열한 문서다. 요구사항서가 "무엇을 만들 것인가"를 정의한다면, 본 문서는 "어떤 순서로 어떻게 만들 것인가"를 다룬다.'));
kids.push(P('각 STEP은 앞 단계의 산출물을 입력으로 사용하므로 순서를 지켜 진행한다. 각 절 끝의 [완료 조건]을 충족해야 다음 단계로 넘어간다.'));
kids.push(SP());
kids.push(NOTE('요구사항 ID 표기', '본문의 DR-xx, SR-xx, WR-xx, ER-xx, IR-xx, PR-xx 는 간이 요구사항서의 요구사항 ID를 가리킨다. 구현 중 판단이 필요하면 해당 ID를 요구사항서에서 확인한다.', 'EAF1DD'));

// 2
kids.push(H('2. 전체 구축 로드맵', HeadingLevel.HEADING_1));
kids.push(P('전체 8단계로 구성한다. STEP 1~2는 설계·설정, STEP 3~6은 핵심 구현, STEP 7~8은 데이터 구축과 검증이다.'));
kids.push(SP());
kids.push(table(
  ['STEP', '작업', '주요 산출물', '선행 조건'],
  [
    ['1', '설정 파일 구축', 'config.json, 코드표 파일', '요구사항서 확정'],
    ['2', '폴더 파싱 모듈', '프로파일 판별기, 토큰 파서', 'STEP 1'],
    ['3', '레코드 생성·키 계산', '정규화기, 키 생성기', 'STEP 2'],
    ['4', '검증 및 저장', '검증기, 샤드 기록기', 'STEP 3'],
    ['5', '첨부 파일 처리', '링크/복사 판정기, 해시 계산', 'STEP 3'],
    ['6', '검색 구현', '2단계 검색기, 로컬 인덱스 캐시', 'STEP 4'],
    ['7', '초기 대량 스캔', '폴더 스캔 임포터, 검토 UI', 'STEP 4, 5'],
    ['8', '시험 및 검증', '시험 결과, 성능 측정 리포트', '전 단계'],
  ],
  [1, 3.5, 4, 2.5]
));
kids.push(SP(200));
kids.push(NOTE('구현 순서에 대한 권고', 'STEP 3(키 계산)을 먼저 확정한 뒤 STEP 7(대량 스캔)을 진행한다. 키 규칙이 바뀐 뒤 대량 등록하면 이전 데이터가 검색되지 않아 전량 재작성이 필요하다.', 'FCE4E4'));

// 3
kids.push(H('3. STEP 1. 설정 파일 구축', HeadingLevel.HEADING_1));
kids.push(P('프로그램이 코드 수정 없이 환경 변화에 대응하려면 다음 항목이 반드시 외부 설정으로 분리되어야 한다. (DR-03-2, DR-04-8, DR-05-5, ER-02, ER-06-5)'));

kids.push(H('3.1 분리 대상', HeadingLevel.HEADING_2));
kids.push(table(
  ['설정 항목', '내용', '변경 사유 예시'],
  [
    ['server_root', '공유 폴더 루트 UNC 경로', '서버 IP 변경, 폴더 이전'],
    ['path_profiles', '경로 규칙(v1/v2) 토큰 맵과 판별 규칙', '폴더 명명 규칙 개정'],
    ['code_tables', 'dev_phase, network, status 등 코드값', '개발 단계 항목 추가'],
    ['excel_mapping', 'Excel 파일명·시트·셀 매핑', '업체 양식 변경'],
    ['custom_fields', '확장 항목 정의(이름·타입·순서)', '운영 중 항목 추가'],
    ['db_path', 'JSONL 샤드 파일 위치', 'DB 폴더 이전'],
  ],
  [2.2, 4.3, 3.5]
));

kids.push(H('3.2 설정 파일 예시', HeadingLevel.HEADING_2));
kids.push(CODE([
  '{',
  '  "server_root": "\\\\\\\\192.168.1.226\\\\12_통신신뢰성검증",',
  '  "db_path": "99_이슈DB",',
  '  "default_profile": "v2",',
  '',
  '  "code_tables": {',
  '    "dev_phase":      ["DV", "PV", "Pilot"],',
  '    "network":        ["CAN", "CAN-FD", "LIN", "Ethernet"],',
  '    "status":         ["진행중", "완료", "보류중"],',
  '    "occurred_phase": ["검증전", "검증중"]',
  '  },',
  '',
  '  "custom_fields": [',
  '    { "key": "category", "label": "분류", "type": "string", "order": 1 }',
  '  ]',
  '}',
]));
kids.push(NOTE('[완료 조건]', 'server_root 를 바꾸었을 때 프로그램 재컴파일 없이 다른 서버를 바라보는지 확인한다. 코드 안에 UNC 경로 문자열이 하드코딩되어 있으면 안 된다.', 'EAF1DD'));

// 4
kids.push(H('4. STEP 2. 폴더 파싱 모듈', HeadingLevel.HEADING_1));
kids.push(P('사용자가 폴더를 선택하면 검증 대상 정보를 자동으로 채우는 모듈이다. 처리 순서는 판별 → 분해 → 토큰 파싱 → 사양 결정이다.'));

kids.push(H('4.1 프로파일 판별 (ER-07)', HeadingLevel.HEADING_2));
kids.push(P('아래 순서로 판정하고, 결과를 화면에 표시하여 사용자가 수정할 수 있게 한다.'));
kids.push(table(
  ['순위', '판정 조건', '결과'],
  [
    ['1', 'WP03_과제결과물 하위 1단계가 "N차" 패턴', 'v1'],
    ['2', 'WP03 하위가 2단계이고 1단계에 사양번호(ES숫자) 포함', 'v2'],
    ['3', '과제 폴더 토큰 7개 & 3번째가 상위 고객 폴더명과 일치', 'v1'],
    ['4', '과제 폴더 토큰 5개', 'v2'],
    ['5', '위 조건 모두 불일치', 'v2 제시 + 사용자 확인'],
  ],
  [1, 6.5, 2.5]
));

kids.push(H('4.2 경로 분해 (ER-06)', HeadingLevel.HEADING_2));
kids.push(P('server_root 를 제거한 상대경로를 계층별로 분해한다. 고객명은 반드시 상위 폴더에서 취한다. 신버전(v2) 과제 폴더명에는 고객 토큰이 없기 때문이다. (ER-06-2)'));
kids.push(CODE([
  '상대경로: 121_통신검증/1211_Supplier/에스엘/01_HKMC/{과제폴더}/WP03_과제결과물/...',
  '',
  '  company  = 에스엘        (Supplier 하위 1단계)',
  '  customer = HKMC          (01_HKMC 에서 접두번호 제거)',
]));

kids.push(H('4.3 과제 폴더 토큰 파싱', HeadingLevel.HEADING_2));
kids.push(table(
  ['토큰', 'v2 (현행)', 'v1 (레거시)'],
  [
    ['1', 'project_no', 'project_no'],
    ['2', 'vehicle_model', 'project_status'],
    ['3', 'ecu_name', '고객명(검증용, 미저장)'],
    ['4', 'design_specs', 'vehicle_model'],
    ['5', 'customer_manager', 'ecu_name'],
    ['6', '-', 'design_specs'],
    ['7', '-', 'customer_manager'],
  ],
  [1, 4, 4]
));
kids.push(SP(120));
kids.push(P('설계 사양 토큰은 콤마로 사양을 분리한 뒤, 각 사양에서 괄호 안 문자열을 variant 로 분리한다. (DR-02-1b)'));
kids.push(CODE([
  '입력: "ES90700-02(SW), ES90700-00(SW), ES95480-13"',
  '',
  '출력: [ { spec: "ES90700-02", variant: "SW"   },',
  '        { spec: "ES90700-00", variant: "SW"   },',
  '        { spec: "ES95480-13", variant: null } ]',
]));

kids.push(H('4.4 평가 사양 결정 (ER-08)', HeadingLevel.HEADING_2));
kids.push(P('이슈는 평가 사양 1개에 귀속되므로 eval_spec 은 반드시 결정되어야 한다. 미결정 상태로는 저장할 수 없다.'));
kids.push(table(
  ['프로파일', '결정 방법'],
  [
    ['v2', '결과물 폴더명 "ES90700-02 - Ch" 의 " - " 앞부분을 자동 추출'],
    ['v1 (사양 1개)', 'design_specs 의 유일한 원소를 자동 지정'],
    ['v1 (사양 2개 이상)', '사용자에게 목록을 제시하고 선택하도록 요구'],
    ['공통', 'Excel 에 평가 사양 항목이 있으면 Excel 값 우선'],
  ],
  [2.5, 7.5]
));
kids.push(NOTE('[완료 조건]', '실제 과제 폴더를 v2 15개, v1 15개 이상 투입하여 파싱 결과를 육안 대조한다. 판별 실패나 토큰 불일치가 발생한 폴더는 목록화하여 명명 규칙 예외로 정리한다.', 'EAF1DD'));

// 5
kids.push(H('5. STEP 3. 레코드 생성과 키 계산', HeadingLevel.HEADING_1));
kids.push(P('이 단계가 시스템 전체에서 가장 중요하다. 키 규칙이 한 번 확정되어 데이터가 쌓이면 이후 변경 비용이 매우 크다.'));

kids.push(H('5.1 처리 순서', HeadingLevel.HEADING_2));
kids.push(NUM('원본 값 정규화 — 좌우 공백 제거, 대문자 변환, 연속 공백 1개 축약, 전각/반각 통일 (DR-04-4)'));
kids.push(NUM('target_key 계산 — 형상 7개 필드 결합 후 SHA-256 앞 16자리 (DR-04-2)'));
kids.push(NUM('scope_key 계산 — target_key 와 eval_spec 결합 후 SHA-256 앞 16자리 (DR-04-3)'));
kids.push(NUM('레코드 조립 — meta / target / issue / attachments / custom_fields'));
kids.push(SP(120));
kids.push(CODE([
  'norm(s) = 공백정리(대문자(trim(s)))',
  '',
  'target_key = SHA256(',
  '    norm(company)  + "|" + norm(customer)      + "|" +',
  '    norm(vehicle_model) + "|" + norm(dev_phase) + "|" +',
  '    norm(ecu_name) + "|" + norm(hw_version)    + "|" +',
  '    norm(sw_version)',
  ')[0:16]',
  '',
  'scope_key  = SHA256( target_key + "|" + norm(eval_spec) )[0:16]',
]));

kids.push(H('5.2 키 계산에서 반드시 지킬 것', HeadingLevel.HEADING_2));
kids.push(table(
  ['금지 사항', '이유'],
  [
    ['project_no 를 키에 포함',
     '신규 과제는 항상 0건이 조회되어 과거 이슈 재활용이라는\n시스템 목적 자체가 성립하지 않는다 (DR-04-5)'],
    ['eval_spec 의 접미 번호 절단\n(예: ES90700-02 → ES90700)',
     'ES90700-02 와 ES90700-00 은 서로 다른 사양이다.\n병합하면 무관한 이슈가 섞인다 (DR-04-3a)'],
    ['custom_fields 를 키에 포함',
     '확장 항목 추가 시점 전후로 키가 달라져\n과거 레코드가 검색에서 누락된다 (DR-05-4)'],
    ['정규화 없이 원본 문자열 사용',
     '"HKMC" 와 "hkmc " 가 다른 키가 되어\n동일 형상이 분리 저장된다'],
  ],
  [3.5, 6.5]
));
kids.push(NOTE('[완료 조건]', '동일 형상·동일 사양을 v1 경로와 v2 경로에서 각각 입력했을 때 scope_key 가 동일하게 산출되는지 확인한다. (DR-04-7)', 'EAF1DD'));

// 6
kids.push(H('6. STEP 4. 검증 및 저장', HeadingLevel.HEADING_1));

kids.push(H('6.1 최소 검증 (DR-06)', HeadingLevel.HEADING_2));
kids.push(P('JSONL 은 DB 엔진이 제약을 강제하지 않으므로 이 검증기가 유일한 방어선이다. 저장 직전에 4종을 수행한다.'));
kids.push(table(
  ['검증', '내용', '실패 시'],
  [
    ['필수 필드', '요구사항서 필수(●) 항목이 모두 존재하고 공란이 아닌지', '저장 차단'],
    ['코드값', 'dev_phase / network / status / occurred_phase 가\n코드표 값과 완전 일치하는지', '저장 차단'],
    ['형식', '일시는 ISO 8601, file_hash 는 SHA-256 형식인지', '저장 차단'],
    ['참조', 'eval_spec 이 design_specs 중 하나와 일치하는지', '경고 후 확인'],
  ],
  [1.8, 5.7, 2.5]
));
kids.push(SP(120));
kids.push(P('대량 입력 시에는 건별로 차단하지 않고 위반 건을 목록화하여 일괄 수정할 수 있어야 한다. 1,000건 등록 중 한 건씩 막히면 작업이 불가능하다. (DR-06-6)'));

kids.push(H('6.2 저장 — 샤드 방식 (WR-05)', HeadingLevel.HEADING_2));
kids.push(P('DB 가 SMB 공유 폴더에 있고 최대 4명이 동시에 사용하므로, 한 파일에 여러 사용자가 append 하면 라인이 깨질 수 있다. 사용자별 파일 분리로 충돌을 원천 차단한다.'));
kids.push(CODE([
  '99_이슈DB/',
  '  ├ issues_chanhwi.jsonl     ← 본인만 쓰기, 타인은 읽기 전용',
  '  ├ issues_userB.jsonl',
  '  ├ issues_userC.jsonl',
  '  └ issues_userD.jsonl',
  '',
  '논리적 DB = 모든 샤드 파일의 합집합',
]));
kids.push(SP(120));
kids.push(P('저장은 파일 처리 → JSONL append → 인덱스 갱신 순으로 수행하며, 중간 실패 시 전체를 롤백한다. (WR-04)'));

kids.push(H('6.3 수정과 삭제 (DR-01-3)', HeadingLevel.HEADING_2));
kids.push(BULLET('기존 라인을 물리적으로 수정하거나 삭제하지 않는다'));
kids.push(BULLET('수정: revision 을 +1 한 새 라인을 append'));
kids.push(BULLET('삭제: is_deleted = true 인 새 라인을 append'));
kids.push(BULLET('조회 시 issue_id 별로 최신 revision 만 취하고 is_deleted 는 제외 (SR-07)'));
kids.push(NOTE('[완료 조건]', '두 대 이상의 PC 에서 동시에 저장하며 라인 손상이 없는지, 상대방이 저장한 레코드가 조회에 반영되는지 확인한다.', 'EAF1DD'));

// 7
kids.push(H('7. STEP 5. 첨부 파일 처리', HeadingLevel.HEADING_1));
kids.push(P('파일은 이미 서버 공유 폴더에 체계적으로 보관되어 있으므로, 별도 저장소로 복사하지 않고 기존 폴더를 저장소로 사용한다. (DR-03-1)'));

kids.push(H('7.1 판정 흐름', HeadingLevel.HEADING_2));
kids.push(CODE([
  '지정한 파일이 과제 폴더 내부에 있는가?',
  '',
  '  ├─ 예  → link_mode = "link"',
  '  │        복사하지 않음. 상대경로 + 해시만 기록',
  '  │',
  '  └─ 아니오 → link_mode = "copy"',
  '             {과제폴더}/{결과물경로}/_이슈첨부/{issue_id}/ 로 복사',
  '             복사본 경로 + 해시 기록',
]));

kids.push(H('7.2 경로 기록 규칙', HeadingLevel.HEADING_2));
kids.push(table(
  ['규칙', '내용'],
  [
    ['상대경로만 저장', 'server_root 기준 상대경로. UNC 절대경로 저장 금지 (DR-03-2)'],
    ['원본 불변', '원본 파일을 이동·삭제·변경하지 않는다 (DR-03-5)'],
    ['해시 기록', '저장 시점 SHA-256 을 남겨 이후 변경·유실을 탐지 (DR-03-6)'],
    ['미리보기', 'JPG, PNG, PDF 는 is_preview = true'],
    ['썸네일', '생성한다면 클라이언트 로컬에. 공유 폴더에 만들지 않는다'],
  ],
  [2.5, 7.5]
));

// 8
kids.push(H('8. STEP 6. 검색 구현', HeadingLevel.HEADING_1));

kids.push(H('8.1 2단계 검색 (SR-01, SR-02)', HeadingLevel.HEADING_2));
kids.push(P('사양이 다르면 동일 이슈가 성립하지 않으므로, 기본 검색은 scope_key 완전 일치다. 결과가 없거나 부족할 때만 범위를 넓힌다.'));
kids.push(table(
  ['단계', '키', '의미', '화면 표기'],
  [
    ['①', 'scope_key', '동일 형상 + 동일 사양', '기본 결과'],
    ['②', 'target_key', '동일 형상, 타 사양', '[타 사양] 참고용'],
    ['③', 'target_key 부분', 'HW/SW 버전만 상이', '[유사 형상]'],
  ],
  [1, 2.2, 4, 2.8]
));
kids.push(SP(120));
kids.push(P('②단계 결과는 참고용이며 동일 이슈로 간주해서는 안 된다. 화면에서 반드시 구분 표기한다.'));

kids.push(H('8.2 인덱스 캐시 (PR-03)', HeadingLevel.HEADING_2));
kids.push(NOTE('가장 흔한 사고 유형',
  'SQLite 등 파일 락 기반 DB 를 SMB 공유 폴더에 두면 안 된다. SMB 는 파일 락이 신뢰할 수 없어 다중 접속 시 캐시가 손상된다. 인덱스 캐시는 반드시 각 PC 로컬(%LOCALAPPDATA%)에 생성한다.',
  'FCE4E4'));
kids.push(SP(160));
kids.push(P('캐시 갱신은 각 샤드 파일의 크기와 수정 시각을 비교하여 변경분만 증분 로드한다. (PR-04) 인덱스는 scope_key 와 target_key 두 키 모두에 대해 구성한다. (PR-05)'));

kids.push(H('8.3 단계별 도입 권고', HeadingLevel.HEADING_2));
kids.push(table(
  ['단계', '방식', '도입 시점'],
  [
    ['1', 'JSONL 전체를 메모리에 로드하여 검색', '초기 구현. 수만 건까지 충분'],
    ['2', '로컬 인덱스 캐시 파일 추가', '기동 시간이 30초를 넘을 때'],
    ['3', '로컬 SQLite 파생 캐시', '검색 응답이 3초를 넘을 때'],
  ],
  [1, 4.5, 4.5]
));
kids.push(SP(120));
kids.push(P('어느 단계에서도 JSONL 이 정본이며, 캐시는 손상 시 JSONL 에서 언제든 재생성 가능해야 한다.'));

// 9
kids.push(H('9. STEP 7. 초기 대량 스캔', HeadingLevel.HEADING_1));
kids.push(P('기존 과제 폴더를 순회하여 이슈 레코드 초안을 자동 생성한다. 초기 구축기에는 하루 1,000건 이상을 등록할 예정이므로 이 기능의 완성도가 구축 기간을 좌우한다. (WR-12)'));
kids.push(SP(120));
kids.push(NUM('대상 상위 폴더를 지정한다'));
kids.push(NUM('과제 폴더별로 프로파일(v1/v2)을 자동 판별한다'));
kids.push(NUM('폴더명을 파싱하여 target 블록을 채운다'));
kids.push(NUM('v2 는 사양 폴더 단위로 레코드를 분리 생성한다'));
kids.push(NUM('WP03 하위 파일을 첨부 후보로 수집한다'));
kids.push(NUM('source = "bulk_scan" 으로 표시하고 미확정 필드는 검토 대기 상태로 둔다'));
kids.push(NUM('사용자가 일괄 검토·수정한 뒤 커밋한다. 커밋 전에는 DB 에 반영하지 않는다'));
kids.push(SP(160));
kids.push(table(
  ['필수 기능', '이유'],
  [
    ['중복 방지 (해시 기준)', '재실행 시 같은 이슈가 다시 등록되는 것을 막는다'],
    ['실패 목록 리포트', '프로파일 판별 실패·사양 미결정 폴더를 따로 모아 수동 처리'],
    ['중단·재개', '수천 건 스캔 중 중단되어도 처음부터 다시 하지 않도록'],
    ['백그라운드 실행', '스캔 중에도 조회 기능이 막히지 않도록 (PR-08)'],
  ],
  [3, 7]
));

// 10
kids.push(H('10. STEP 8. 시험 및 검증', HeadingLevel.HEADING_1));
kids.push(H('10.1 기능 시험 체크리스트', HeadingLevel.HEADING_2));
kids.push(table(
  ['구분', '확인 항목', '판정'],
  [
    ['파싱', 'v2 폴더 15개 이상 파싱 결과가 육안 대조와 일치', '□'],
    ['파싱', 'v1 폴더 15개 이상 파싱 결과가 육안 대조와 일치', '□'],
    ['파싱', '프로파일 자동 판별이 정확하고, 수동 전환이 동작', '□'],
    ['키', 'v1·v2 동일 형상에서 scope_key 가 동일하게 산출', '□'],
    ['키', '사양만 다를 때 scope_key 가 다르게 산출', '□'],
    ['검증', '코드표에 없는 상태값 입력 시 저장이 차단', '□'],
    ['검증', '필수 필드 누락 시 저장이 차단되고 항목이 표시', '□'],
    ['저장', '2대 이상 PC 동시 저장 시 라인 손상 없음', '□'],
    ['저장', '수정 시 새 리비전이 생기고 이전 리비전이 보존', '□'],
    ['검색', 'scope_key 일치 이슈가 기본 결과로 표시', '□'],
    ['검색', '타 사양 결과가 구분 표기되어 나타남', '□'],
    ['첨부', '과제 폴더 내부 파일이 복사 없이 링크로 기록', '□'],
    ['첨부', '외부 파일이 지정 위치로 복사되고 원본이 유지', '□'],
    ['첨부', 'JPG/PNG/PDF 미리보기 동작', '□'],
    ['확장', '설정에서 확장 항목 추가 시 기존 레코드가 정상 조회', '□'],
  ],
  [1.3, 7.4, 1.3]
));

kids.push(H('10.2 성능 측정', HeadingLevel.HEADING_2));
kids.push(table(
  ['항목', '목표', '측정 조건'],
  [
    ['검색 응답', '3초 이내', '이슈 50,000건'],
    ['최초 기동', '30초 이내', '전체 로드'],
    ['재기동', '5초 이내', '캐시 활용'],
    ['라인 크기', '32KB 이하', '첨부 다수 레코드'],
  ],
  [2.5, 3, 4.5]
));
kids.push(SP(120));
kids.push(P('샘플 5,000건을 생성하여 측정하고, 목표 미달 시 8.3의 단계별 도입 권고에 따라 캐시를 추가한다.'));

// 11
kids.push(new Paragraph({ children: [new PageBreak()] }));
kids.push(H('11. 반드시 지킬 금지 사항', HeadingLevel.HEADING_1));
kids.push(P('아래는 발견이 늦을수록 복구 비용이 커지는 항목이다. 구현 착수 전에 팀 전원이 공유한다.'));
kids.push(SP(120));
kids.push(table(
  ['금지 사항', '발생하는 문제', '근거'],
  [
    ['SQLite 등 락 기반 캐시를\n공유 폴더에 배치',
     'SMB 파일 락 불안정으로 다중 접속 시\n캐시 파일 손상', 'PR-03'],
    ['한 JSONL 파일에\n여러 사용자가 동시 append',
     '라인이 섞여 파손. 복구 시 손상 구간\n판별이 어려움', 'WR-05'],
    ['키 구성 필드를\n운영 중 변경',
     '변경 전후 레코드의 키가 달라져\n과거 이슈가 통째로 검색 누락', 'DR-05-3'],
    ['eval_spec 계열 병합\n(ES90700-02 → ES90700)',
     '서로 다른 사양의 이슈가 섞여\n검색 결과 신뢰도 상실', 'DR-04-3a'],
    ['DB 에 UNC 절대경로 저장',
     '서버 IP 변경 시 전체 레코드\n일괄 수정 필요', 'DR-03-2'],
    ['원본 파일 이동·삭제',
     '다른 업무 흐름이 깨지고\n기존 링크가 유실', 'DR-03-5'],
    ['기존 JSONL 라인을\n직접 수정·삭제',
     '이력 추적 불가. 동시 접근 중\n파일 파손 위험', 'DR-01-3'],
  ],
  [3, 4.5, 1.5]
));

// 12
kids.push(H('12. 부록. 레코드 구조 요약', HeadingLevel.HEADING_1));
kids.push(P('레코드는 코어 4블록과 확장 1블록으로 구성된다. 코어는 구조가 고정되며, 변경은 schema_version 상향으로만 수행한다.'));
kids.push(SP(120));
kids.push(table(
  ['블록', '역할', '변경 가능성'],
  [
    ['meta', '레코드 관리 정보, 검색 키 2종', '고정'],
    ['target', '검증 대상 정보(제어기 형상, 사양, 경로)', '고정'],
    ['issue', '이슈 내용(제목, 평가명, 상태, 조치)', '고정'],
    ['attachments[]', '첨부 파일 경로·해시·유형', '고정'],
    ['custom_fields', '사용자 정의 확장 항목', '운영 중 자유 추가'],
  ],
  [2.2, 5.8, 2]
));
kids.push(SP(200));
kids.push(P('확장 항목은 프로그램 설정에서 추가·수정·삭제할 수 있으며, 검색 키 계산에는 관여하지 않는다. 사용 빈도가 높아진 항목은 코어 필드로 승격할 수 있다. (DR-05)'));
kids.push(SP(300));
kids.push(new Paragraph({
  children: [new TextRun({ text: '— 이상 —', font: FONT, size: 20, color: '888888' })],
  alignment: AlignmentType.CENTER,
}));

// ---------- doc ----------
const doc = new Document({
  numbering: {
    config: [
      { reference: 'bul', levels: [
        { level: 0, format: LevelFormat.BULLET, text: '•', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 500, hanging: 240 } } } },
        { level: 1, format: LevelFormat.BULLET, text: '–', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 900, hanging: 240 } } } },
      ]},
      { reference: 'num', levels: [
        { level: 0, format: LevelFormat.DECIMAL, text: '%1.', alignment: AlignmentType.LEFT,
          style: { paragraph: { indent: { left: 500, hanging: 280 } } } },
      ]},
    ],
  },
  styles: {
    default: {
      document: { run: { font: FONT, size: 20 } },
    },
  },
  sections: [{
    properties: {
      page: { margin: { top: 1400, bottom: 1400, left: 1400, right: 1400 } },
    },
    children: kids,
  }],
});

Packer.toBuffer(doc).then(buf => {
  fs.writeFileSync('/sessions/beautiful-focused-bardeen/mnt/outputs/SCH_이슈관리DB_구축실행가이드.docx', buf);
  console.log('OK', buf.length);
});
