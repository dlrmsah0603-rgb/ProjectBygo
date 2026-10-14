class PackingItem {
  String id;
  String name;
  bool isChecked;

  PackingItem({
    required this.id,
    required this.name,
    this.isChecked = false,
  });

  // 기기 로컬 저장소에 저장하기 위해 Map(JSON) 형태로 변환
  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'isChecked': isChecked,
      };

  // 로컬 저장소에서 불러온 Map(JSON) 데이터를 다시 객체로 변환
  factory PackingItem.fromJson(Map<String, dynamic> json) => PackingItem(
        id: json['id'],
        name: json['name'],
        isChecked: json['isChecked'] ?? false,
      );
}

// 2. 외출 상황(프리셋) 클래스 (예: 운동 갈 때, 출근할 때)
class Situation {
  String id;
  String title; // 상황 이름 (예: "운동", "출근")
  String tag; // 연동할 태그명 (예: "#운동")
  List<PackingItem> items; // 이 상황에 챙겨야 할 소지품 리스트

  Situation({
    required this.id,
    required this.title,
    required this.tag,
    required this.items,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'tag': tag,
        'items': items.map((item) => item.toJson()).toList(),
      };

  factory Situation.fromJson(Map<String, dynamic> json) => Situation(
        id: json['id'],
        title: json['title'],
        tag: json['tag'],
        items: (json['items'] as List<dynamic>)
            .map((item) => PackingItem.fromJson(item))
            .toList(),
      );
}