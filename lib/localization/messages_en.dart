import 'package:meta/meta.dart';

/// English for the Kazakh texts that live in tables rather than at a call:
/// names of furniture, materials and stages, checklists, and the messages
/// the design core returns. Keyed by the Kazakh text, like [ruText]'s
/// table; anything missing here falls back to Russian.
const _enByKk = <String, String>{
  // Kazakh rows already written in Russian words.
  'Газоблок D500': 'Aerated block D500',
  'Ламинат / плитка': 'Laminate / tile',
  'Алдынан': 'Front',
  'Қазақ ауыл үйі': 'Kazakh village house',
  'Бір қабат, үш бөлме': 'One floor, three rooms',
  'Бір қабат, бес бөлме': 'One floor, five rooms',
  'Екі қабатты үй': 'Two floors',
  '1,5 м шұңқыр қазып, топырақ пен жер асты суын қарау':
      'Dig a 1.5 m test pit, check the soil and groundwater',
  'XPS жылытқыш': 'XPS insulation',
  'Ілгіш': 'Coat rack',
  'Іргетас': 'Foundation',
  'Ішкі сылақ': 'Interior plaster',
  'Азық шкафы': 'Pantry cabinet',
  'Алдынан (кіреберіс)': 'Front (entrance)',
  'Арматура байланғаннан кейін суретке түсірілді':
      'Rebar photographed after tying',
  'Артынан': 'Back',
  'Ас үй': 'Kitchen',
  'Ас үй мен қонақ бөлме байланыспайды':
      "Kitchen and living room aren't connected",
  'Ас үй мен қонақ бөлме жалғасқан': 'Kitchen and living room are connected',
  'Ас үстелі': 'Dining table',
  'Ас үстелі мен қонақ бөлме жалғасқан, тамақты дәліз арқылы айналып әкелмейсіз.':
      "The dining area and living room are connected, so food doesn't go the long way round through the corridor.",
  'Асхана': 'Dining room',
  'Аудан аз': 'Small area',
  'Аула және қосалқы құрылыс': 'Yard and outbuildings',
  'Ашылу бағытын тек есікке өзгертуге болады':
      "Only a door's swing direction can be changed",
  'Аяқ киім шкафы': 'Shoe cabinet',
  'Бар есік-тереземен қабаттасады, сәл жылжытыңыз':
      'Overlaps existing windows and doors; move it a little',
  'Бар қабырғаға тым жақын': 'Too close to an existing wall',
  'Бар қабырғаға тым жақын: теңестіріңіз не кемінде 0,30 м қалдырыңыз':
      'Too close to an existing wall: align it or leave at least 0.30 m',
  'Баспалдақ орнын қабырға толық алып жатыр.':
      'The stair space is fully taken by a wall.',
  'Баспалдақ сыймайды': "The stairs don't fit",
  'Баспалдақ қабырға арқылы өтпейді, алдымен қабырғаны жылжытыңыз не жойыңыз':
      "Stairs can't pass through a wall; move or delete the wall first",
  'Баспалдақтан аулақ болыңыз': "Don't touch the stairs",
  'Баспалдақтан тыс тордан бастаңыз': 'Start from a cell outside the stairs',
  'Баспалдақтың үстінде қабат болуы керек':
      'There must be a floor above the stairs',
  'Бұл баспалдақ табылмады': "These stairs weren't found",
  'Бұл қабат табылмады': "This floor wasn't found",
  'Баспалдақ үйдің ішінде болуы керек': 'Stairs must be inside the house',
  'Қабырға сызығына тым жақын: тура келтіріңіз не кемінде 0,30 м қалдырыңыз':
      'Too close to a wall line: align with it or leave at least 0.30 m',
  'Баспалдақ түгелдей бір бөлменің ішінде тұруы керек':
      'The stairs must stand entirely in one room',
  'Мұнда баспалдақ бар': 'There are stairs here already',
  'Бөлме қосу': 'Add a room',
  'Бөлме +': 'Room +',
  'Басты кіреберіс': 'Main entrance',
  'Басты кіреберіс бірінші қабаттың сыртқы қабырғасындағы есік болуы керек.':
      'The main entrance must be a door in a ground-floor outer wall.',
  'Басты кіреберіс есік болуы керек': 'The main entrance must be a door',
  'Басты кіреберіс әлі белгіленбеген, бірінші қабаттың сыртқы есігінде орнатыңыз.':
      "The main entrance isn't set yet; make a ground-floor outer door the main entrance.",
  'Басылған орын қабырғада емес': "The tap point isn't on a wall",
  'Басқа': 'Other',
  'Басқа құралдар': 'More tools',
  'Батыс': 'West',
  'Белгілеу, ұзындық, ен және диагональды тексеру':
      'Setting out, checking length, width and diagonals',
  'Бояу және еден жабыны': 'Painting and floor covering',
  'Бу оқшаулағыш': 'Vapour barrier',
  'Бу оқшаулағыш пен жылытқыш үзіліссіз':
      'Vapour barrier and insulation without gaps',
  'Бір кісілік төсек': 'Single bed',
  'Біреуін жылжытыңыз.': 'Move one of the buildings.',
  'Бірінші қатар блок деңгеймен қаланды': 'First block course laid level',
  'Бүйірінен': 'Side',
  'Бүкіл үйді тексеру: есік-терезе, су, электр, жылу':
      'Whole-house check: windows and doors, water, electrical, heating',
  'Бұл бөлу сызығы табылмады': "This dividing line wasn't found",
  'Бұл жерде қабырға бар, бар қабырғаның ұшын созыңыз':
      "There's a wall here already; extend the end of the existing wall",
  'Бұл қабырға басқасымен орны ортақ, кемінде 0,30 м жылжытыңыз':
      'This wall overlaps another; move it at least 0.30 m',
  'Бұл қабырға табылмады, қайта таңдаңыз':
      "This wall wasn't found; select again",
  'Бұл қабырға өзгерді, қайта таңдаңыз': 'This wall changed; select again',
  'Бұл өзгеріс баспалдаққа әсер етеді, алдымен баспалдақты түзетіңіз':
      'This change affects the stairs; fix the stairs first',
  'Бұл өзгеріс бөлмені бөледі не жояды, басқа орын таңдаңыз':
      'This change would split or delete a room; pick another spot',
  'Бұл өзгеріс есік-терезеге әсер етеді, алдымен оларды жылжытыңыз':
      'This change affects windows and doors; move them first',
  'Бұл өзгеріс есік-терезеге әсер етеді, олардан аулақ орын таңдаңыз':
      'This change affects windows and doors; pick a spot away from them',
  'Бұл өлшем есік-терезеге әсер етеді, алдымен оларды жылжытыңыз':
      'This size affects windows and doors; move them first',
  'Бөлек': 'Detached',
  'Бөлек қабырға': 'Detached wall',
  'Бөлме': 'Room',
  'Бөлме баспалдақты жаппауы керек': 'The room must not overlap the stairs',
  'Бөлме сызу': 'Draw a room',
  'Бөлме тар': 'Narrow room',
  'Бөлме үйдің ішінде, ені мен ұзындығы кемінде 0,30 м болуы керек':
      'The room must be inside the house, at least 0.30 m wide and long',
  'Бөлмені бір кеңістік ішінде сызыңыз': 'Draw the room within one space',
  'Бөлменің есігі жоқ': 'The room has no door',
  'Бөлу': 'Split',
  'Бөлу бар есік-терезеге әсер етеді, олардан аулақ орын таңдаңыз':
      'The split affects existing windows and doors; pick a spot away from them',
  'Бөлу сызығы есік-терезеге әсер етеді, басқа орын таңдаңыз':
      'The dividing line affects windows and doors; pick another spot',
  'Бөлу сызығы көршісінен аспауы керек, аралық кемінде 0,30 м':
      'The dividing line must not cross the neighbouring one; keep at least 0.30 m',
  'Бөлу сызығы осы кеңістік арқылы өтуі керек':
      'The dividing line must pass through this space',
  'Бөлу сызығын кеңістік ішінде сызыңыз':
      'Draw the dividing line inside the space',
  'Бөлінбеген орын бар': "There's unassigned space",
  'Газ қазандығы': 'Gas boiler',
  'Гидрооқшау': 'Waterproofing',
  'Гидрооқшау не жабын төселді': 'Waterproofing or roof covering laid',
  'Гидрооқшау: 2 қабат битумды мембрана немесе ПВХ':
      'Waterproofing: 2 layers of bitumen membrane or PVC',
  'Гильзалардың орны тексерілді': 'Sleeve positions checked',
  'Дайындық және құжаттар': 'Preparation and paperwork',
  'Дөңгелек үстел': 'Round table',
  'Еден жылуы әлсіз': 'Weak floor insulation',
  'Еден және әрлеу': 'Floors and finishes',
  'Еден тегістеу не жылы еден': 'Floor screed or underfloor heating',
  'Екі есік-терезе қабырғада қабаттасып тұр, біреуін жылжытыңыз.':
      'Two openings on a wall overlap; move one of them.',
  'Есік': 'Door',
  'Есік алды алаңы': 'Entrance landing',
  'Есік қосу': 'Add a door',
  'Есік-терезе': 'Windows and doors',
  'Есік-терезе ашық бөлікке қойылған.':
      'A window or door is on an open stretch of wall.',
  'Есік-терезе ойығының үстінде аркалық':
      'Lintel over window and door openings',
  'Есік-терезе орны жарамсыз': 'Invalid window or door position',
  'Есік-терезе тұрған жерде қабырға жоқ.':
      "There's no wall where the window or door is.",
  'Есік-терезе қабаттасады': 'Windows and doors overlap',
  'Есік-терезе қабаттың таза биіктігінен биік.':
      'A window or door is taller than the clear floor height.',
  'Есік-терезе қабырғадан ұзын не қабырға түйіскен жерді кесіп өтеді.':
      'A window or door is longer than the wall or crosses a wall junction.',
  'Есік-терезе қабырғаға сыймайды, орнын не өлшемін өзгертіңіз':
      "The window or door doesn't fit in the wall; change its position or size",
  'Еңіс жасайтын жылытқыш (сына XPS / керамзит) 30–150':
      'Tapered insulation (wedge XPS / expanded clay) 30–150',
  'Жабын аралығы үлкен': 'Large floor span',
  'Жабын плитасы не шатыр қаңқасы дайын': 'Floor slab or roof frame ready',
  'Жазу үстелі': 'Desk',
  'Жалғас қабырға 0,30 м-ден қысқа болады, азырақ жылжытыңыз':
      'The adjoining wall would be shorter than 0.30 m; move it less',
  'Жалғау орны есік-терезе арқылы өтпейді, басқа орын таңдаңыз':
      "A wall junction can't pass through a window or door; pick another spot",
  'Жастық': 'Bed',
  'Жасырын жұмыстар жабылмас бұрын суретке түсірілді':
      'Hidden work photographed before being covered',
  'Жатын бөлме': 'Bedroom',
  'Жатын бөлмеде терезе жоқ': 'The bedroom has no window',
  'Жатын бөлмелердің жарығы мен желдетуі қамтамасыз етілген.':
      'Bedrooms have light and ventilation.',
  'Жаңа қабат': 'New layer',
  'Жер учаскесі мен құрылыс рұқсатын рәсімдеу':
      'Land registration and building permit',
  'Жиһаз': 'Furniture',
  'Жиһаз id қайталанады': 'Duplicate furniture id',
  'Жиһаз қою': 'Place furniture',
  'Жоба күйі жарамсыз': 'Invalid design state',
  'Жоғарыдан': 'From above',
  'Жоғарғы қабат жойылса, төменгі баспалдақтың жалғасы қалмайды. Оларды да жоюды растаңыз':
      'Deleting the top floor leaves the stairs below with nowhere to go. Confirm that they should be deleted too',
  'Жуыну бөлмесі': 'Bathroom',
  'Жуыну бөлмесі біреу ғана': 'Only one bathroom',
  'Жуыну бөлмесі мен ас үйде екінші гидрооқшау':
      'Second waterproofing layer in the bathroom and kitchen',
  'Жылу жүйесі сумен сыналды': 'Heating system pressure-tested with water',
  'Жұмыс үстелі': 'Kitchen counter',
  'Зат': 'Item',
  'Кемінде бір қабат қалуы керек': 'At least one floor must remain',
  'Кемінде бір құрылым қабаты қалуы керек':
      'At least one build-up layer must remain',
  'Киім шкафы': 'Wardrobe',
  'Кілем': 'Carpet',
  'Кір жуғыш': 'Washing machine',
  'Кіреберіс есіктің тығыздығы тексерілді': 'Front door seal checked',
  'Кәріз еңісі тексерілді': 'Drain slope checked',
  'Көлденең не тік қабырға тартыңыз': 'Draw a horizontal or vertical wall',
  'Көрпеше': 'Korpe',
  'Көрші қабырға сызығынан аспаңыз, кемінде 0,30 м қалдырыңыз':
      "Don't cross the neighbouring wall line; leave at least 0.30 m",
  'Көше жақтан қақпа қосыңыз; көлік кіретін болса ені кемінде 3,5 м.':
      'Add a gate on the street side; if a car will drive in, make it at least 3.5 m wide.',
  'Минералды мақта жылытқыш': 'Mineral wool insulation',
  'Мұнда бірнеше қабырғаға ортақ баптау бар, алдымен әдепкі қалыңдықты қайтарыңыз':
      "There's a setting shared by several walls here; restore the default thickness first",
  'Науа мен су құбыры орнатылды': 'Gutters and downpipes installed',
  'Оны жоюға не басқа қабырғаға жылжытуға болады.':
      'You can delete it or move it to another wall.',
  'Оны учаске ішіне жылжытыңыз не учаске өлшемін өзгертіңіз.':
      'Move the item inside the plot or change the plot size.',
  'Ор жобалық тереңдікке дейін қазылып, табаны тығыздалды':
      'Trench dug to design depth, bottom compacted',
  'Орындық': 'Chair',
  'Оңтүстік': 'South',
  'Параметрлер жарамсыз, бастапқы жоба сақталды':
      'Invalid parameters; the original design is kept',
  'Сандық, жүк': 'Blanket chest',
  'Саңылау кеңейетін лентамен бітелді': 'Gap sealed with expanding tape',
  'Солтүстік': 'North',
  'Солтүстіктің төрт бағытының бірін таңдаңыз':
      'Choose one of the four north directions',
  'Су құбыры қысыммен сыналды': 'Water supply pressure-tested',
  'Су, электр, жылу': 'Water, electrical, heating',
  'Су-электр': 'Electrical and water',
  'Су-электр нүктелері': 'Electrical and water points',
  'Сызба, келісімшарт және суреттерді сақтау':
      'Keep the drawings, contract and photos',
  'Сызықпен бөлу': 'Split with a line',
  'Сызықты жойсаңыз, көрші торлар бірігеді, бөлмелерге, баспалдаққа не есік-терезеге әсер етеді.':
      'Deleting the line merges neighbouring cells, affecting rooms, stairs or windows and doors.',
  'Сыртқы XPS пен гидрооқшау біткен соң ғана көму':
      'Backfill only after outer XPS and waterproofing',
  'Сыртқы контурды жоюға болмайды': "The outer outline can't be deleted",
  'Сыртқы қабырға жылуы әлсіз': 'Weak outer wall insulation',
  'Сыртқы қабырғаны үй өлшемі арқылы өзгертіңіз':
      'Change an outer wall through the house size',
  'Сыртқы әрлеу (жұқа сылақ/панель)':
      'Exterior finish (thin-coat render/panels)',
  'Сөре': 'Shelf',
  'Тақырыпты жазыңыз': 'Enter a name',
  'Тегіс шатырдан қыста қар өздігінен түспейді, жабын плитасы мен арматура жергілікті қар жүктемесі бойынша есептелуі керек. Су қабылдағыш парапетте, құбыр мен қабылдағышқа электр жылытқыш қойыңыз. Парапет ішіне гидрооқшауды кемінде 300 мм көтеріңіз.':
      "Snow doesn't slide off a flat roof in winter, so size the slab and rebar for the local snow load. Put the roof drain in the parapet and fit heating cable on the pipe and drain. Take the waterproofing at least 300 mm up the inside of the parapet.",
  'Тегіс шатырдың қар жүктемесі мен су ағызуы':
      'Flat roof snow load and drainage',
  'Тегістеу (жылы еден)': 'Screed (underfloor heating)',
  'Тек бір қабаттағы бөлмелерді біріктіруге болады':
      'Only rooms on the same floor can be merged',
  'Тек көрші бөлмелерді біріктіруге болады':
      'Only neighbouring rooms can be merged',
  'Теледидар тұғыры': 'TV stand',
  'Темірбетон жабын плитасы (монолит немесе ПК)':
      'Reinforced concrete floor slab (cast-in-place or precast)',
  'Темірбетон плита': 'Reinforced concrete slab',
  'Терезе': 'Window',
  'Терезе жақтауы жылытқышқа жақын орнатылды':
      'Window frame set closer to the insulation',
  'Терезе жылуы әлсіз': 'Weak window insulation',
  'Терезе қосу': 'Add a window',
  'Терезеден жылу көп кетеді': 'A lot of heat escapes through the windows',
  'Тор үйдің шегінен шығады': 'The cell is outside the house',
  'Тоңазытқыш': 'Fridge',
  'Тығыз минералды мақта плита': 'Dense mineral wool board',
  'Тығыздалған топырақ': 'Compacted soil',
  'Түзету': 'Edit',
  'Тұскиіз': 'Tus kiiz',
  'Төбе сылағы / аспалы төбе': 'Ceiling plaster / suspended ceiling',
  'Төменгі баспалдақтың жоғарғы қабаты қалмайды, оларды да жоюды растаңыз':
      'The stairs below would have no floor above; confirm that they should be deleted too',
  'Төсек': 'Bed',
  'Уақытша су мен электр қосу': 'Temporary water and power hookup',
  'Цемент тегістеу (тормен)': 'Cement screed (with mesh)',
  'Шатыр': 'Roof',
  'Шатыр жылуы әлсіз': 'Weak roof insulation',
  'Шекара өлшемін үйдің ені мен тереңдігі арқылы өзгертіңіз':
      'Change the boundary size through the house width and depth',
  'Шолу': 'Overview',
  'Шығыс': 'East',
  'Электр қалқаны мен желілер сызба бойынша':
      'Electrical panel and circuits as drawn',
  'Қабылдау және кіру': 'Acceptance and moving in',
  'Қабырға': 'Wall',
  'Қабырға баспалдақ арқылы өтпейді': "A wall can't pass through the stairs",
  'Қабырға және плиталар': 'Walls and floors',
  'Қабырға кемінде 0,30 м болуы керек': 'A wall must be at least 0.30 m',
  'Қабырға координаталары тым көп, жоспарды ретке келтіріңіз':
      'Too many wall coordinates; tidy up the plan',
  'Қабырға орынды толық алды': 'Walls take up all the space',
  'Қабырға салу': 'Build a wall',
  'Қабырға сылағы': 'Wall plaster',
  'Қабырға қысқа, бұл есік-терезе сыймайды':
      "The wall is short; this window or door won't fit",
  'Қабырға үйдің ішінде болуы керек': 'The wall must be inside the house',
  'Қабырғаны жойсаңыз, ондағы есік-терезе де жойылады, растаңыз':
      'Deleting the wall also deletes its windows and doors; please confirm',
  'Қабырғаны түзету': 'Edit wall',
  'Қабырғаның тіктігі тексерілді': 'Wall plumb checked',
  'Қалқа қабырғалардың астында іргетас жоқ': 'No foundation under partitions',
  'Қақтығысты шешу нұсқасы жарамсыз': 'Invalid conflict resolution option',
  'Қиыршық тас': 'Crushed stone',
  'Қолжуғыш': 'Washbasin',
  'Қонақ бөлме': 'Living room',
  'Қонақ келгенде жатын бөлмеге қонақ бөлме арқылы өтесіз, оңашалық әлсіз. Есік алдына қалқа жасаңыз не есікті дәліз жағына ауыстырыңыз.':
      "When guests come you'll have to pass through the living room to the bedroom, so there's little privacy. Put a partition in front of the door or move the door to the corridor side.",
  'Қоршау және қақпа': 'Fence and gate',
  'Қоршауда қақпа жоқ': 'The fence has no gate',
  'Қосалқы құрылыс үйдің үстінде тұрмауы керек, жылжытыңыз.':
      "An outbuilding can't stand where the house is; move it.",
  'Қосалқы құрылыстар': 'Outbuildings',
  'Құйылғаннан кейін кемінде 7 күн күтім':
      'Cure the concrete for at least 7 days after pouring',
  'Құм төсеме': 'Sand bed',
  'Құм-қиыршық қабат-қабатымен тығыздалды':
      'Sand and gravel bed compacted in layers',
  'Құрылысшымен баға мен мерзімі жазылған жазбаша келісімшарт':
      'Written contract with the builder stating price and dates',
  'Үй учаскеден шығып тұр': 'The house extends beyond the plot',
  'Үй шекараға жақын': 'The house is close to the boundary',
  'Үй өлшемі': 'House size',
  'Үйге кіру': 'Moving in',
  'Үйдің айналасына отмостка': 'Apron around the house',
  'Үстел': 'Table',
  'Үстінен': 'Top',
  'Ұзын орындық': 'Bench',
  'Әр жатын бөлмеде сыртқы терезе бар': 'Every bedroom has an outside window',
  'Әр қабатта белдеу не арматуралы белбеу':
      'A ring beam or bond beam on every floor',
  'Әрекет параметрлері жарамсыз': 'Invalid action parameters',
  'Өзгертетін нысан табылмады': "The item to change wasn't found",
  'Өзгертілген қабырғаға бар есік-терезе сыймайды':
      "Existing windows and doors don't fit the changed wall",
  'Өлшем': 'Size',
  'Бөлме мен баспалдақ үйдің сыртында (кесілген бұрышта) тұра алмайды':
      "Rooms and stairs can't stand outside the house (in the cut corner)",
  'Бұл сызық кесілген бұрыштың шеті, алдымен тіктөртбұрыш пішінді қайтарыңыз':
      'This line is the edge of a cut corner; restore the rectangle first',
  'Кесілетін бұрыш кемінде 0,60 м, ал үйге кемінде 1,50 м қалуы керек':
      'The cut must be at least 0.60 m and the house must keep at least 1.50 m',
  'Кесік шеті бар қабырғаға тым жақын: теңестіріңіз не кемінде 0,30 м қалдырыңыз':
      'The cut edge is too close to a wall: align it or leave at least 0.30 m',
  'Кесілетін бұрышта баспалдақ бар, алдымен оны жылжытыңыз':
      'There are stairs in the corner being cut; move them first',
  'Бұл қабат онсыз да толық тіктөртбұрыш':
      'This floor is already a full rectangle',
  'Атауын жазыңыз': 'Enter a name',
  'Жер телімі әлі жоқ': "The site isn't set up yet",
  'Кірістірілген кезеңді жоюға болмайды, оны орындалды деп белгілеңіз':
      "A built-in stage can't be deleted; mark it done",
  'Қосатын нүкте жоқ': 'No points to add',
  'Тазартатын нүкте жоқ': 'No points to delete',
  'Қабат биіктігі 2400 мм-ден кем болмауы керек':
      "Floor height can't be less than 2400 mm",
  'Қабырға қалыңдығы 60–600 мм болуы керек':
      'Wall thickness must be 60 to 600 mm',
  'Ені нөлден үлкен болуы керек': 'Width must be greater than zero',
  'Биіктігі нөлден үлкен болуы керек': 'Height must be greater than zero',
  'Терезе алды биіктігі теріс болмауы керек': "Sill height can't be negative",
  'Орын қашықтығы теріс болмауы керек': "Distance can't be negative",
  'Кемінде бір қабат керек': 'At least one floor is needed',
  'Еңіс 1–60° болуы керек': 'Slope must be 1 to 60°',
  'Шатыр шығыңқысы 0–1500 мм болуы керек': 'Roof overhang must be 0 to 1500 mm',
  'Парапет биіктігі 0–1500 мм болуы керек':
      'Parapet height must be 0 to 1500 mm',
  'Үйдің ені 3–100 м болуы керек': 'House width must be 3 to 100 m',
  'Үйдің тереңдігі 3–100 м болуы керек': 'House depth must be 3 to 100 m',
  'Баспалдақты жоғарғы қабатқа қоюға болмайды':
      "Stairs can't go on the top floor",
  'Диван': 'Sofa',
  'Алаша': 'Handwoven rug',
  'Плита': 'Stove',
  'Раковина': 'Sink',
  'Ванна': 'Bathtub',
  'Душ': 'Shower',
  'Унитаз': 'Toilet',
  'Терраса': 'Terrace',
  'Дәретхана есігі асүйге ашылады': 'The bathroom door faces the kitchen',
  'Асүйде не қонақ бөлмеде терезе жоқ':
      'The kitchen or living room has no window',
  'Есік тар': 'The door is narrow',
  'Кіреберіс': 'Hall',
  'Дәліз': 'Corridor',
  'Қойма': 'Storeroom',
  'Қазандық': 'Boiler room',
};

/// The English for a Kazakh table text, or null when there is none.
String? enText(String kk) => _enByKk[kk];

/// Whether [kk] has an English text.
@visibleForTesting
bool hasEnText(String kk) => _enByKk.containsKey(kk);
