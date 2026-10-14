class Schedule {
  String id;
  String title; // 일정 이름 (예: "저녁 헬스장 가기")
  DateTime dateTime; // 일정 날짜 및 시간
  String? tag; // 태그 (선택 사항)
  String? situationId; // 연결된 상황(Situation)의 ID (예: '운동' 프리셋 연결)
  bool isCompleted; // 일정 자체의 완료 여부

  Schedule({
    required this.id,
    required this.title,
    required this.dateTime,
    this.tag,
    this.situationId,
    this.isCompleted = false,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'dateTime': dateTime.toIso8601String(), // 날짜를 문자열로 변환해 저장
        'tag': tag,
        'situationId': situationId,
        'isCompleted': isCompleted,
      };

  factory Schedule.fromJson(Map<String, dynamic> json) => Schedule(
        id: json['id'],
        title: json['title'],
        dateTime: DateTime.parse(json['dateTime']), // 문자열을 다시 날짜 객체로 복원
        tag: json['tag'],
        situationId: json['situationId'],
        isCompleted: json['isCompleted'] ?? false,
      );
}