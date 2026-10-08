# 작업 규칙

## MT5 입력값 언급 시 전략테스트 명칭 매칭 필수

사용자에게 백테스트/최적화를 위해 특정 입력값(input)을 바꿔달라고 요청할 때는,
**반드시 그 입력값의 `.mq5` 코드상 정확한 코멘트(`//` 뒤 설명 텍스트)를 함께 적을 것.**
이게 MT5 전략테스터의 Inputs/Optimization 탭에 표시되는 "명칭"이라, 사용자가
변수명만 보고는 어떤 필드인지 헷갈려서 엉뚱한 값을 건드리는 사고가 반복됐음
(예: `UseProtectStop` vs `UseBreakevenStop` 혼동).

예시 형식:
> `ProtectTriggerR` — *"Favorable R to arm protect-lock stop (CONFIRMED user-selected, see header)"* = 0.25로 변경

여러 입력값을 한 번에 안내할 때도 각각 전부 이 형식으로 적을 것 — 하나라도 빠뜨리지 말 것.
