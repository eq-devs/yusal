import 'package:flutter/material.dart';
import '../app/settings.dart';
import '../core/document/house_document.dart';

/// Chinese / Kazakh names of furniture kinds, sleeves and layer materials.
const furnitureNames = <FurnitureKind, (String, String)>{
  FurnitureKind.bed: ('双人床', 'Төсек'),
  FurnitureKind.singleBed: ('单人床', 'Бір кісілік төсек'),
  FurnitureKind.wardrobe: ('衣柜', 'Киім шкафы'),
  FurnitureKind.table: ('桌子', 'Үстел'),
  FurnitureKind.diningTable: ('餐桌', 'Ас үстелі'),
  FurnitureKind.chair: ('椅子', 'Орындық'),
  FurnitureKind.sofa: ('沙发', 'Диван'),
  FurnitureKind.desk: ('书桌', 'Жазу үстелі'),
  FurnitureKind.tvStand: ('电视柜', 'Теледидар тұғыры'),
  FurnitureKind.shelf: ('置物架', 'Сөре'),
  FurnitureKind.rug: ('地毯', 'Кілем'),
  FurnitureKind.alasha: ('手织地垫', 'Алаша'),
  FurnitureKind.wallRug: ('挂毯', 'Тұскиіз'),
  FurnitureKind.korpe: ('褥垫', 'Көрпеше'),
  FurnitureKind.cushion: ('靠垫', 'Жастық'),
  FurnitureKind.dastarkhan: ('矮圆桌', 'Дөңгелек үстел'),
  FurnitureKind.sandyq: ('木箱+被褥垛', 'Сандық, жүк'),
  FurnitureKind.bench: ('长凳', 'Ұзын орындық'),
  FurnitureKind.hooks: ('衣挂', 'Ілгіш'),
  FurnitureKind.counter: ('操作台', 'Жұмыс үстелі'),
  FurnitureKind.stove: ('灶台', 'Плита'),
  FurnitureKind.sink: ('水槽', 'Раковина'),
  FurnitureKind.fridge: ('冰箱', 'Тоңазытқыш'),
  FurnitureKind.pantry: ('储物柜', 'Азық шкафы'),
  FurnitureKind.bathtub: ('浴缸', 'Ванна'),
  FurnitureKind.shower: ('淋浴', 'Душ'),
  FurnitureKind.toilet: ('马桶', 'Унитаз'),
  FurnitureKind.basin: ('台盆', 'Қолжуғыш'),
  FurnitureKind.washer: ('洗衣机', 'Кір жуғыш'),
  FurnitureKind.boiler: ('燃气锅炉', 'Газ қазандығы'),
  FurnitureKind.shoeCabinet: ('鞋柜', 'Аяқ киім шкафы'),
  FurnitureKind.terrace: ('露台', 'Терраса'),
  FurnitureKind.porch: ('门廊', 'Есік алды алаңы'),
  FurnitureKind.custom: ('物品', 'Зат'),
};

String furnitureName(FurnitureKind kind) {
  final n = furnitureNames[kind]!;
  return tr(n.$1, n.$2);
}

/// Floor coverings are drawn first so furniture sits on them.
bool isFlatFurniture(FurnitureKind kind) =>
    kind == FurnitureKind.rug || kind == FurnitureKind.alasha;

/// Groups for the furniture palette.
List<(String, List<FurnitureKind>)> furnitureGroups() => [
      (
        tr('起居', 'Тұрғын'),
        [
          FurnitureKind.sofa,
          FurnitureKind.table,
          FurnitureKind.chair,
          FurnitureKind.tvStand,
          FurnitureKind.shelf,
          FurnitureKind.desk,
        ]
      ),
      (
        tr('哈萨克传统', 'Қазақы'),
        [
          FurnitureKind.rug,
          FurnitureKind.alasha,
          FurnitureKind.wallRug,
          FurnitureKind.korpe,
          FurnitureKind.cushion,
          FurnitureKind.dastarkhan,
          FurnitureKind.sandyq,
        ]
      ),
      (
        tr('卧室', 'Жатын бөлме'),
        [
          FurnitureKind.bed,
          FurnitureKind.singleBed,
          FurnitureKind.wardrobe,
        ]
      ),
      (
        tr('厨房', 'Ас үй'),
        [
          FurnitureKind.counter,
          FurnitureKind.stove,
          FurnitureKind.sink,
          FurnitureKind.fridge,
          FurnitureKind.pantry,
          FurnitureKind.diningTable,
          FurnitureKind.bench,
        ]
      ),
      (
        tr('卫浴与设备', 'Жуыну, жабдық'),
        [
          FurnitureKind.bathtub,
          FurnitureKind.shower,
          FurnitureKind.toilet,
          FurnitureKind.basin,
          FurnitureKind.washer,
          FurnitureKind.boiler,
        ]
      ),
      (
        tr('门厅与室外', 'Кіреберіс, сыртқы'),
        [
          FurnitureKind.shoeCabinet,
          FurnitureKind.hooks,
          FurnitureKind.porch,
          FurnitureKind.terrace,
          FurnitureKind.custom,
        ]
      ),
    ];

IconData furnitureIcon(FurnitureKind kind) => switch (kind) {
      FurnitureKind.bed || FurnitureKind.singleBed => Icons.bed_outlined,
      FurnitureKind.wardrobe ||
      FurnitureKind.pantry ||
      FurnitureKind.shoeCabinet =>
        Icons.door_sliding_outlined,
      FurnitureKind.table ||
      FurnitureKind.diningTable ||
      FurnitureKind.desk =>
        Icons.table_restaurant_outlined,
      FurnitureKind.chair || FurnitureKind.bench => Icons.chair_alt_outlined,
      FurnitureKind.sofa => Icons.weekend_outlined,
      FurnitureKind.tvStand => Icons.tv_outlined,
      FurnitureKind.shelf => Icons.shelves,
      FurnitureKind.rug ||
      FurnitureKind.alasha ||
      FurnitureKind.korpe =>
        Icons.texture,
      FurnitureKind.wallRug => Icons.wallpaper,
      FurnitureKind.cushion => Icons.crop_portrait,
      FurnitureKind.dastarkhan => Icons.circle_outlined,
      FurnitureKind.sandyq => Icons.inventory_2_outlined,
      FurnitureKind.hooks => Icons.checkroom,
      FurnitureKind.counter => Icons.countertops_outlined,
      FurnitureKind.stove => Icons.local_fire_department_outlined,
      FurnitureKind.sink || FurnitureKind.basin => Icons.wash_outlined,
      FurnitureKind.fridge => Icons.kitchen_outlined,
      FurnitureKind.bathtub => Icons.bathtub_outlined,
      FurnitureKind.shower => Icons.shower_outlined,
      FurnitureKind.toilet => Icons.wc_outlined,
      FurnitureKind.washer => Icons.local_laundry_service_outlined,
      FurnitureKind.boiler => Icons.fireplace_outlined,
      FurnitureKind.terrace || FurnitureKind.porch => Icons.deck_outlined,
      FurnitureKind.custom => Icons.category_outlined,
    };

String sleeveName(SleeveKind kind) => switch (kind) {
      SleeveKind.sewer => tr('下水', 'Кәріз'),
      SleeveKind.water => tr('给水', 'Су'),
      SleeveKind.power => tr('电缆', 'Кабель'),
      SleeveKind.gas => tr('燃气', 'Газ'),
    };

String materialName(LayerMaterial m) => switch (m) {
      LayerMaterial.conc => tr('混凝土', 'Бетон'),
      LayerMaterial.block => tr('砌块', 'Блок'),
      LayerMaterial.ins => tr('保温', 'Жылытқыш'),
      LayerMaterial.earth => tr('土', 'Топырақ'),
      LayerMaterial.sand => tr('砂石', 'Құм-қиыршық'),
      LayerMaterial.plaster => tr('抹灰', 'Сылақ'),
      LayerMaterial.metal => tr('卷材', 'Мембрана'),
      LayerMaterial.wood => tr('木/地板', 'Ағаш/еден'),
      LayerMaterial.film => tr('薄膜', 'Пленка'),
      LayerMaterial.gyp => tr('石膏板', 'Гипс'),
    };

String roomTypeName(RoomType type) => switch (type) {
      RoomType.living => tr('客厅', 'Қонақ бөлме'),
      RoomType.bedroom => tr('卧室', 'Жатын бөлме'),
      RoomType.kitchen => tr('厨房', 'Ас үй'),
      RoomType.bathroom => tr('卫生间', 'Жуыну бөлмесі'),
      RoomType.dining => tr('餐厅', 'Асхана'),
      RoomType.custom => tr('房间', 'Бөлме'),
    };
