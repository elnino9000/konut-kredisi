import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

void main() => runApp(const KrediApp());

const kYesil = Color(0xFF2F6B5B);
const kKehribar = Color(0xFFB7791F);
const kKirmizi = Color(0xFFB3403A);
const kVadeler = [12, 24, 36, 48, 60, 72, 84, 96, 108, 120];
const kEvdsAdres = 'https://evds3.tcmb.gov.tr/igmevdsms-dis/';
const kTahsisOrani = 0.005; // kredi tahsis ücreti üst sınırı: binde 5
const kKdv = 0.20;

class KrediApp extends StatelessWidget {
  const KrediApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Konut Kredisi Hesabı',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: kYesil),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: kYesil,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const AnaSayfa(),
    );
  }
}

// ---------- Yardımcı hesaplar ----------

String tlSade(double v) {
  final neg = v < 0;
  final s = v.abs().round().toString();
  final b = StringBuffer();
  for (int i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) b.write('.');
    b.write(s[i]);
  }
  return '${neg ? '-' : ''}$b';
}

String tl(double v) => '${tlSade(v)} TL';

String yuzde(double v, [int basamak = 2]) =>
    '%${v.toStringAsFixed(basamak).replaceAll('.', ',')}';

String oranYaz(double v) => v.toStringAsFixed(2).replaceAll('.', ',');

double paraOku(String s) {
  final t = s
      .replaceAll('.', '')
      .replaceAll(' ', '')
      .replaceAll('TL', '')
      .replaceAll(',', '.');
  return double.tryParse(t) ?? 0;
}

double oranOku(String s) =>
    double.tryParse(s.replaceAll(',', '.').replaceAll('%', '').trim()) ?? 0;

double taksitHesapla(double anapara, double aylikOran, int ay) {
  if (anapara <= 0 || ay <= 0) return 0;
  if (aylikOran == 0) return anapara / ay;
  return anapara * aylikOran / (1 - pow(1 + aylikOran, -ay));
}

/// Eline geçen net para ile taksitlerin eşitlendiği aylık oran (masraflar dahil gerçek maliyet).
double aylikGercekMaliyet(double netAlinan, double taksit, int ay) {
  if (netAlinan <= 0 || taksit <= 0) return 0;
  double alt = 0;
  double ust = 1;
  for (int j = 0; j < 100; j++) {
    final orta = (alt + ust) / 2;
    final bugun = taksit * (1 - pow(1 + orta, -ay)) / orta;
    if (bugun > netAlinan) {
      alt = orta;
    } else {
      ust = orta;
    }
  }
  return (alt + ust) / 2;
}

double yillikBilesik(double aylik) => pow(1 + aylik, 12).toDouble() - 1;

/// BDDK 29.01.2026 kararı: konut değeri ve enerji sınıfına göre
/// azami kredi / değer oranı. sinif: 0 = A-B, 1 = C, 2 = D ve altı.
double maxKrediOrani(double deger, int sinif) {
  const bantlar = [
    [5000000.0, 0.9, 0.8, 0.7],
    [7000000.0, 0.8, 0.7, 0.6],
    [10000000.0, 0.7, 0.6, 0.5],
    [20000000.0, 0.5, 0.4, 0.3],
  ];
  for (final b in bantlar) {
    if (deger <= b[0]) return b[1 + sinif];
  }
  return const [0.4, 0.3, 0.2][sinif];
}

/// Eldeki parayla (peşinat + tüm masraflar) alınabilecek en pahalı ev.
double enYuksekFiyat(double para, int sinif, double sabitMasraf,
    double tapuOrani, double emlakOrani) {
  const sinirlar = [5000000.0, 7000000.0, 10000000.0, 20000000.0, double.infinity];
  double sonuc = 0;
  double alt = 0;
  for (final ust in sinirlar) {
    final o = maxKrediOrani(alt + 1, sinif);
    final f = (para - sabitMasraf) /
        ((1 - o) + tapuOrani + emlakOrani + kTahsisOrani * o);
    if (f <= alt) break;
    if (f <= ust) {
      sonuc = f;
      break;
    }
    sonuc = ust;
    alt = ust;
  }
  return max(0.0, sonuc);
}

class Teklif {
  Teklif(this.ad, this.oran);
  final String ad;
  final double oran;
}

// ---------- Merkez Bankası (EVDS) ----------

class EvdsSonuc {
  EvdsSonuc(this.deger, this.tarih);
  final double deger;
  final String tarih;
}

String _evdsTarih(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${d.month.toString().padLeft(2, '0')}-${d.year}';

Future<EvdsSonuc?> evdsSonDeger(
    String adres, String key, String seri, int gun, int? formul) async {
  final bit = DateTime.now();
  final bas = bit.subtract(Duration(days: gun));
  var url =
      '${adres}series=$seri&startDate=${_evdsTarih(bas)}&endDate=${_evdsTarih(bit)}&type=json';
  if (formul != null) url += '&formulas=$formul';
  final yanit = await http
      .get(Uri.parse(url), headers: {'key': key})
      .timeout(const Duration(seconds: 20));
  if (yanit.statusCode != 200) {
    throw Exception('sunucu ${yanit.statusCode} kodu döndü ($seri)');
  }
  final veri = jsonDecode(utf8.decode(yanit.bodyBytes));
  final items = (veri is Map) ? veri['items'] : null;
  if (items is! List) throw Exception('beklenmeyen yanıt ($seri)');
  final alanBasi = seri.replaceAll('.', '_');
  for (final item in items.reversed) {
    if (item is! Map) continue;
    for (final e in item.entries) {
      final k = e.key.toString();
      if (!k.startsWith(alanBasi)) continue;
      final v = double.tryParse(e.value?.toString().replaceAll(',', '.') ?? '');
      if (v != null) return EvdsSonuc(v, item['Tarih']?.toString() ?? '');
    }
  }
  return null;
}

// ---------- Ana sayfa ----------

class AnaSayfa extends StatefulWidget {
  const AnaSayfa({super.key});

  @override
  State<AnaSayfa> createState() => _AnaSayfaState();
}

class _AnaSayfaState extends State<AnaSayfa> {
  final Map<String, TextEditingController> c = {
    'para': TextEditingController(text: '400.000'),
    'fiyat': TextEditingController(text: '2.600.000'),
    'faiz': TextEditingController(text: '2,90'),
    'enflasyon': TextEditingController(text: '29,77'),
    'gelir': TextEditingController(text: ''),
    'ekspertiz': TextEditingController(text: '21.004'),
    'doner': TextEditingController(text: '2.534'),
    'banka': TextEditingController(text: '5.000'),
    'sigorta': TextEditingController(text: '0'),
  };
  int sinif = 0;
  bool tapuTamami = true;
  bool emlakci = true;
  bool emlakTamami = false;
  double senaryo = 0;
  String faizKaynagi = 'Varsayılan (6 Kasım 2026 piyasa ortalaması)';
  String enfNotu = 'TÜİK Ekim 2026: yıllık %29,77, aylık %2,58';
  List<Teklif> teklifler = [
    Teklif('Kuveyt Türk', 2.87),
    Teklif('Vakıf Katılım', 2.94),
  ];
  SharedPreferences? prefs;

  @override
  void initState() {
    super.initState();
    _yukle();
  }

  @override
  void dispose() {
    for (final x in c.values) {
      x.dispose();
    }
    super.dispose();
  }

  Future<void> _yukle() async {
    final p = await SharedPreferences.getInstance();
    prefs = p;
    for (final e in c.entries) {
      final v = p.getString('girdi_${e.key}');
      if (v != null) e.value.text = v;
    }
    final kayitli = p.getStringList('teklifler');
    if (!mounted) return;
    setState(() {
      sinif = p.getInt('sinif') ?? 0;
      tapuTamami = p.getBool('tapuTamami') ?? true;
      emlakci = p.getBool('emlakci') ?? true;
      emlakTamami = p.getBool('emlakTamami') ?? false;
      faizKaynagi = p.getString('faizKaynagi') ?? faizKaynagi;
      enfNotu = p.getString('enfNotu') ?? enfNotu;
      if (kayitli != null) {
        teklifler = [
          for (final s in kayitli)
            if (s.contains('|'))
              Teklif(s.split('|').first, double.tryParse(s.split('|').last) ?? 0),
        ];
      }
    });
  }

  void _kaydet() {
    final p = prefs;
    if (p == null) return;
    for (final e in c.entries) {
      p.setString('girdi_${e.key}', e.value.text);
    }
    p.setInt('sinif', sinif);
    p.setBool('tapuTamami', tapuTamami);
    p.setBool('emlakci', emlakci);
    p.setBool('emlakTamami', emlakTamami);
    p.setString('faizKaynagi', faizKaynagi);
    p.setString('enfNotu', enfNotu);
    p.setStringList(
        'teklifler', [for (final t in teklifler) '${t.ad}|${t.oran}']);
  }

  void _degisti() {
    setState(() {});
    _kaydet();
  }

  // ----- Temel değerler -----

  double get para => paraOku(c['para']!.text);
  double get fiyat => paraOku(c['fiyat']!.text);
  double get aylikFaiz => (oranOku(c['faiz']!.text) + senaryo) / 100;
  double get yillikEnf => oranOku(c['enflasyon']!.text);
  double get aylikEnf => pow(1 + yillikEnf / 100, 1 / 12).toDouble() - 1;

  double get tapuOrani => tapuTamami ? 0.04 : 0.02;
  double get emlakOrani =>
      emlakci ? (emlakTamami ? 0.04 : 0.02) * (1 + kKdv) : 0.0;
  double get tapu => fiyat * tapuOrani;
  double get emlak => fiyat * emlakOrani;
  double get ekspertiz => paraOku(c['ekspertiz']!.text);
  double get doner => paraOku(c['doner']!.text);
  double get banka => paraOku(c['banka']!.text);
  double get sigorta => paraOku(c['sigorta']!.text);

  /// Ev fiyatına bağlı olmayan sabit masraflar.
  double get sabitMasraf => doner + ekspertiz + banka + sigorta;

  /// Eldeki para önce masraflara gider, kalanı peşinat olur, eksik kısım kredidir.
  double get kredi {
    final k = (fiyat - (para - tapu - emlak - sabitMasraf)) / (1 - kTahsisOrani);
    return max(0.0, min(k, fiyat));
  }

  double get tahsis => kredi * kTahsisOrani;
  double get toplamMasraf => tapu + emlak + sabitMasraf + tahsis;
  double get pesinat => para - toplamMasraf;

  /// Krediye bağlı (banka tarafı) masraflar: gerçek maliyet hesabına girer.
  double get krediMasrafi => tahsis + ekspertiz + banka + sigorta;

  // ----- Merkez Bankası verisi -----

  Future<void> _ayarlar() async {
    final p = prefs ?? await SharedPreferences.getInstance();
    final anahtar = TextEditingController(text: p.getString('evdsKey') ?? '');
    final adres =
        TextEditingController(text: p.getString('evdsAdres') ?? kEvdsAdres);
    final faizSeri =
        TextEditingController(text: p.getString('faizSeri') ?? 'TP.KTF12');
    final enfSeri =
        TextEditingController(text: p.getString('enfSeri') ?? 'TP.FG.J0');
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Merkez Bankası bağlantısı'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                  'evds3.tcmb.gov.tr adresinde ücretsiz hesap açın. Profilim sayfasındaki API anahtarını kopyalayıp aşağıya yapıştırın.'),
              const SizedBox(height: 8),
              TextField(
                controller: anahtar,
                decoration: const InputDecoration(labelText: 'API anahtarı'),
              ),
              TextField(
                controller: adres,
                decoration: const InputDecoration(labelText: 'Servis adresi'),
              ),
              TextField(
                controller: faizSeri,
                decoration: const InputDecoration(
                    labelText: 'Konut kredisi faizi seri kodu'),
              ),
              TextField(
                controller: enfSeri,
                decoration:
                    const InputDecoration(labelText: 'TÜFE seri kodu'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              p.setString('evdsKey', anahtar.text.trim());
              p.setString('evdsAdres', adres.text.trim());
              p.setString('faizSeri', faizSeri.text.trim());
              p.setString('enfSeri', enfSeri.text.trim());
              Navigator.pop(ctx);
            },
            child: const Text('Kaydet'),
          ),
        ],
      ),
    );
  }

  Future<void> _veriCek() async {
    final messenger = ScaffoldMessenger.of(context);
    final p = prefs ?? await SharedPreferences.getInstance();
    final key = p.getString('evdsKey') ?? '';
    if (key.isEmpty) {
      messenger.showSnackBar(const SnackBar(
          content: Text('Önce Merkez Bankası API anahtarınızı girin.')));
      await _ayarlar();
      return;
    }
    final adres = p.getString('evdsAdres') ?? kEvdsAdres;
    final faizSeri = p.getString('faizSeri') ?? 'TP.KTF12';
    final enfSeri = p.getString('enfSeri') ?? 'TP.FG.J0';
    messenger.showSnackBar(
        const SnackBar(content: Text('Merkez Bankası verisi alınıyor...')));
    final hatalar = <String>[];
    var basarili = false;

    try {
      final faiz = await evdsSonDeger(adres, key, faizSeri, 90, null);
      if (faiz != null) {
        c['faiz']!.text = oranYaz(faiz.deger / 12);
        faizKaynagi =
            'Merkez Bankası konut kredisi ortalaması: yıllık ${yuzde(faiz.deger)} (${faiz.tarih})';
        basarili = true;
      } else {
        hatalar.add('faiz serisinde veri yok');
      }
    } catch (e) {
      hatalar.add('faiz: $e');
    }

    try {
      final yillik = await evdsSonDeger(adres, key, enfSeri, 150, 3);
      final aylik = await evdsSonDeger(adres, key, enfSeri, 150, 1);
      if (yillik != null) {
        c['enflasyon']!.text = oranYaz(yillik.deger);
        enfNotu = 'Merkez Bankası (TÜİK verisi): yıllık ${yuzde(yillik.deger)}'
            '${aylik != null ? ', aylık ${yuzde(aylik.deger)}' : ''} (${yillik.tarih})';
        basarili = true;
      } else {
        hatalar.add('TÜFE serisinde veri yok');
      }
    } catch (e) {
      hatalar.add('enflasyon: $e');
    }

    if (basarili) _degisti();
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(SnackBar(
      duration: Duration(seconds: hatalar.isEmpty ? 4 : 10),
      content: Text(hatalar.isEmpty
          ? 'Faiz ve enflasyon güncellendi.'
          : 'Bazı veriler alınamadı: ${hatalar.join(' / ')}. Değerleri elle girebilirsiniz.'),
    ));
  }

  // ----- Banka teklifleri -----

  Future<void> _teklifEkle() async {
    final ad = TextEditingController();
    final oran = TextEditingController();
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Banka teklifi ekle'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: ad,
              decoration: const InputDecoration(labelText: 'Banka adı'),
            ),
            TextField(
              controller: oran,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration:
                  const InputDecoration(labelText: 'Aylık faiz (%)'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            onPressed: () {
              final o = oranOku(oran.text);
              if (ad.text.trim().isNotEmpty && o > 0) {
                teklifler.add(Teklif(ad.text.trim(), o));
                _degisti();
              }
              Navigator.pop(ctx);
            },
            child: const Text('Ekle'),
          ),
        ],
      ),
    );
  }

  void _teklifKullan(Teklif t) {
    c['faiz']!.text = oranYaz(t.oran);
    faizKaynagi = '${t.ad} teklifi';
    _degisti();
  }

  // ----- Arayüz parçaları -----

  Widget _baslik(String metin) {
    return Padding(
      padding: const EdgeInsets.only(top: 22, bottom: 4),
      child: Text(
        metin,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              color: Theme.of(context).colorScheme.primary,
              fontWeight: FontWeight.w700,
            ),
      ),
    );
  }

  Widget _alan(String anahtar, String etiket, {String? ipucu}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: c[anahtar],
        keyboardType: const TextInputType.numberWithOptions(decimal: true),
        decoration: InputDecoration(
          labelText: etiket,
          helperText: ipucu,
          helperMaxLines: 2,
          border: const OutlineInputBorder(),
        ),
        onChanged: (_) => _degisti(),
      ),
    );
  }

  Widget _satir(String sol, String sag, {bool kalin = false, Color? renk}) {
    final st = TextStyle(
        fontWeight: kalin ? FontWeight.w700 : FontWeight.w400, color: renk);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(sol, style: st)),
          Text(sag, style: st),
        ],
      ),
    );
  }

  Widget _kucukNot(String metin) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(metin, style: Theme.of(context).textTheme.bodySmall),
      );

  Widget _ozet() {
    final oran = maxKrediOrani(fiyat, sinif);
    final maxKredi = fiyat * oran;
    final paraYetmiyor = pesinat < 0;
    final krediFazla = kredi > maxKredi + 0.5;
    final uygun = !paraYetmiyor && !krediFazla;
    final renk = uygun ? kYesil : kKirmizi;
    final enYuksek =
        enYuksekFiyat(para, sinif, sabitMasraf, tapuOrani, emlakOrani);

    String durum;
    if (paraYetmiyor) {
      durum = 'Paranız masrafları karşılamıyor';
    } else if (krediFazla) {
      durum = 'Bu evde bu kadar kredi çıkmaz';
    } else {
      durum = 'Bu planla ev alınabilir';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(uygun ? Icons.check_circle : Icons.error, color: renk),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    durum,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: renk, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            _satir('Elinizdeki para', tl(para)),
            _satir('Masraflara giden', tl(toplamMasraf)),
            _satir('Peşinata kalan', tl(pesinat)),
            _satir('Çekilecek kredi', tl(kredi), kalin: true),
            _satir('Kredi / ev değeri',
                yuzde(fiyat > 0 ? kredi / fiyat * 100 : 0, 1)),
            _satir('Bu enerji sınıfında en fazla',
                '${yuzde(oran * 100, 0)} = ${tl(maxKredi)}'),
            if (krediFazla)
              _satir('Gereken ek nakit', tl((kredi - maxKredi) * (1 - kTahsisOrani)),
                  kalin: true, renk: kKirmizi),
            const Divider(height: 20),
            _satir('Bu parayla alınabilecek en pahalı ev', tl(enYuksek),
                kalin: true),
            _kucukNot(
                'Kredi oranı satış fiyatına değil ekspertizin biçtiği değere uygulanır (BDDK 29.01.2026 kararı). Ev sahibi olanlarda oranlar daha düşüktür.'),
          ],
        ),
      ),
    );
  }

  Widget _masrafKarti() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Masraf dökümü',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            _satir('Tapu harcı (${tapuTamami ? '%4' : '%2'})', tl(tapu)),
            _satir('Tapu döner sermaye', tl(doner)),
            if (emlakci)
              _satir(
                  'Emlakçı komisyonu (${emlakTamami ? '%4' : '%2'} + KDV)',
                  tl(emlak)),
            _satir('Ekspertiz (bilirkişi raporu)', tl(ekspertiz)),
            _satir('Kredi tahsis ücreti (binde 5)', tl(tahsis)),
            _satir('İpotek ve diğer banka masrafları', tl(banka)),
            _satir('Sigortalar (ilk yıl)', tl(sigorta)),
            const Divider(),
            _satir('Toplam masraf', tl(toplamMasraf), kalin: true),
            _satir('Bankaya giden kısmı', tl(krediMasrafi)),
            _kucukNot(
                'Konut kredisinde BSMV ve KKDF alınmaz. Kesin banka ücretleri sözleşme öncesi bilgi formunda yazar.'),
          ],
        ),
      ),
    );
  }

  Widget _teklifKarti() {
    final tema = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 8, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text('Banka teklifleri',
                        style: tema.textTheme.titleMedium),
                  ),
                  TextButton.icon(
                    onPressed: _teklifEkle,
                    icon: const Icon(Icons.add),
                    label: const Text('Ekle'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                  'Kullanmak için dokunun, silmek için basılı tutun. Bankadan aldığınız kesin teklifi buraya ekleyin.',
                  style: tema.textTheme.bodySmall),
            ),
            for (final t in teklifler)
              ListTile(
                title: Text(t.ad),
                subtitle: Text(
                    'Aylık ${yuzde(t.oran)}, 120 ayda taksit ${tl(taksitHesapla(kredi, t.oran / 100, 120))}'),
                trailing: oranOku(c['faiz']!.text) == t.oran
                    ? const Icon(Icons.check, color: kYesil)
                    : null,
                onTap: () => _teklifKullan(t),
                onLongPress: () {
                  teklifler.remove(t);
                  _degisti();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _vadeler() {
    final gelir = paraOku(c['gelir']!.text);
    final tema = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Vadelere göre ödeme',
                  style: tema.textTheme.titleMedium),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(
                'Gerçek maliyet: banka masrafları dahil yıllık maliyet. Enflasyondan arındırılmış: yıllık ${yuzde(yillikEnf)} enflasyon sürerse kalan gerçek maliyet. Ay ay plan için satıra dokunun.',
                style: tema.textTheme.bodySmall,
              ),
            ),
            for (final ay in kVadeler) _vadeSatiri(ay, gelir),
          ],
        ),
      ),
    );
  }

  Widget _vadeSatiri(int ay, double gelir) {
    final r = aylikFaiz;
    final t = taksitHesapla(kredi, r, ay);
    final toplam = t * ay;
    double bugun = 0;
    for (int k = 1; k <= ay; k++) {
      bugun += t / pow(1 + aylikEnf, k);
    }
    final gercekAylik = aylikGercekMaliyet(kredi - krediMasrafi, t, ay);
    final gercekYillik = yillikBilesik(gercekAylik);
    final reel = (1 + gercekYillik) / (1 + yillikEnf / 100) - 1;

    String? gelirNotu;
    Color? gelirRenk;
    if (gelir > 0) {
      final o = t / gelir * 100;
      gelirNotu = 'Taksit gelirin ${yuzde(o, 0)} kadarı';
      gelirRenk = o > 50 ? kKirmizi : (o > 35 ? kKehribar : kYesil);
    }
    final kucuk = Theme.of(context).textTheme.bodySmall;
    return InkWell(
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OdemePlani(
            kredi: kredi, aylikFaiz: r, aylikEnf: aylikEnf, ay: ay),
      )),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 64,
              child: Text('$ay ay',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${tl(t)} / ay',
                      style: const TextStyle(fontWeight: FontWeight.w600)),
                  Text('Toplam ${tl(toplam)}, faiz ${tl(toplam - kredi)}',
                      style: kucuk),
                  Text('Bugünkü parayla ${tl(bugun)}', style: kucuk),
                  Text(
                      'Gerçek maliyet yıllık ${yuzde(gercekYillik * 100, 1)}, enflasyondan arındırılmış ${yuzde(reel * 100, 1)}',
                      style: kucuk),
                  if (gelirNotu != null)
                    Text(gelirNotu,
                        style: TextStyle(color: gelirRenk, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final yillikNominal = yillikBilesik(aylikFaiz) * 100;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Konut Kredisi Hesabı'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_download_outlined),
            tooltip: 'Merkez Bankası verisini çek',
            onPressed: _veriCek,
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Bağlantı ayarları',
            onPressed: _ayarlar,
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
        children: [
          _baslik('Paranız ve ev'),
          _alan('para', 'Elinizdeki toplam para (TL)',
              ipucu: 'Masraflar önce bundan düşülür, kalanı peşinat olur'),
          _alan('fiyat', 'Ev fiyatı (TL)'),
          const SizedBox(height: 6),
          const Text('Enerji kimlik belgesindeki sınıf'),
          const SizedBox(height: 6),
          SegmentedButton<int>(
            segments: const [
              ButtonSegment(value: 0, label: Text('A–B')),
              ButtonSegment(value: 1, label: Text('C')),
              ButtonSegment(value: 2, label: Text('D ve altı')),
            ],
            selected: {sinif},
            onSelectionChanged: (s) {
              sinif = s.first;
              _degisti();
            },
          ),
          const SizedBox(height: 12),
          _ozet(),
          _baslik('Faiz'),
          _alan('faiz', 'Aylık faiz (%)'),
          _kucukNot(
              'Kaynak: $faizKaynagi. Bu oran yıllık bileşik ${yuzde(yillikNominal, 1)} demektir.'),
          const SizedBox(height: 10),
          _teklifKarti(),
          const SizedBox(height: 10),
          const Text('Faiz değişirse ne olur?'),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final d in const [-0.5, -0.25, 0.0, 0.25, 0.5])
                ChoiceChip(
                  label: Text(d == 0
                      ? 'Seçili faiz'
                      : '${d > 0 ? '+' : ''}${d.toString().replaceAll('.', ',')} puan'),
                  selected: senaryo == d,
                  onSelected: (_) => setState(() => senaryo = d),
                ),
            ],
          ),
          _baslik('Enflasyon'),
          _alan('enflasyon', 'Yıllık enflasyon (%)'),
          _kucukNot(enfNotu),
          _baslik('Masraflar'),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: tapuTamami,
            title: const Text('Tapu harcının tamamını ben ödüyorum'),
            subtitle: const Text('Açıksa %4, kapalıysa yasal payınız %2'),
            onChanged: (v) {
              tapuTamami = v;
              _degisti();
            },
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: emlakci,
            title: const Text('Emlakçı aracılığıyla alıyorum'),
            subtitle: const Text('Yasal üst sınır: satış bedelinin %2’si + KDV'),
            onChanged: (v) {
              emlakci = v;
              _degisti();
            },
          ),
          if (emlakci)
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: emlakTamami,
              title: const Text('Komisyonun tamamını ben ödüyorum'),
              subtitle:
                  const Text('Yazılı anlaşmayla %4 + KDV alıcıya kalabilir'),
              onChanged: (v) {
                emlakTamami = v;
                _degisti();
              },
            ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Tahmini masrafları düzenle'),
            children: [
              _alan('ekspertiz', 'Ekspertiz / bilirkişi raporu (TL)',
                  ipucu: '2026 ortalaması yaklaşık 21.000 TL'),
              _alan('doner', 'Tapu döner sermaye (TL)',
                  ipucu: '2026 tarifesi 2.534 TL'),
              _alan('banka', 'İpotek ve diğer banka masrafları (TL)',
                  ipucu: 'Kabaca tahmin; bankanın bilgi formundan düzeltin'),
              _alan('sigorta', 'Sigortalar, ilk yıl (TL)',
                  ipucu:
                      'DASK zorunlu; banka genelde konut ve hayat sigortası da ister. Teklif alınca girin.'),
            ],
          ),
          const SizedBox(height: 8),
          _masrafKarti(),
          _baslik('Gelir'),
          _alan('gelir', 'Aylık net gelir (TL)',
              ipucu: 'İsteğe bağlı; taksitin gelire oranını gösterir'),
          const SizedBox(height: 8),
          _vadeler(),
          const SizedBox(height: 16),
          Text(
            'Bu uygulama bilgi amaçlı bir hesaplama aracıdır. Kesin rakamlar için bankanın ödeme planını ve sözleşme öncesi bilgi formunu esas alın.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ---------- Ay ay ödeme planı ----------

class OdemePlani extends StatelessWidget {
  const OdemePlani({
    super.key,
    required this.kredi,
    required this.aylikFaiz,
    required this.aylikEnf,
    required this.ay,
  });

  final double kredi;
  final double aylikFaiz;
  final double aylikEnf;
  final int ay;

  @override
  Widget build(BuildContext context) {
    final t = taksitHesapla(kredi, aylikFaiz, ay);
    final satirlar = <List<double>>[];
    double kalan = kredi;
    for (int k = 1; k <= ay; k++) {
      final faiz = kalan * aylikFaiz;
      final anapara = t - faiz;
      kalan = max(0.0, kalan - anapara);
      satirlar.add(
          [k.toDouble(), faiz, anapara, kalan, t / pow(1 + aylikEnf, k)]);
    }
    const kucuk = TextStyle(fontSize: 11.5);
    final baslikStil = kucuk.copyWith(fontWeight: FontWeight.w700);

    Widget hucre(String s, int flex, TextStyle st, {bool sola = false}) =>
        Expanded(
          flex: flex,
          child: Text(s,
              style: st, textAlign: sola ? TextAlign.left : TextAlign.right),
        );

    return Scaffold(
      appBar: AppBar(title: Text('$ay ay ödeme planı')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Aylık taksit ${tl(t)}',
                    style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Kredi ${tl(kredi)}, toplam ödeme ${tl(t * ay)}'),
                const SizedBox(height: 8),
                Text(
                  'Erken kapama: "Kalan borç" tutarına ek olarak, kalan vade 36 aydan uzunsa en fazla %2, kısaysa en fazla %1 erken ödeme tazminatı alınabilir. "Bugünkü değer", o ayki taksitin bugünün parasıyla karşılığıdır.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                hucre('Ay', 2, baslikStil, sola: true),
                hucre('Faiz', 4, baslikStil),
                hucre('Anapara', 4, baslikStil),
                hucre('Kalan borç', 5, baslikStil),
                hucre('Bugünkü değer', 5, baslikStil),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: satirlar.length,
              itemBuilder: (_, idx) {
                final s = satirlar[idx];
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  child: Row(
                    children: [
                      hucre('${s[0].toInt()}', 2, kucuk, sola: true),
                      hucre(tlSade(s[1]), 4, kucuk),
                      hucre(tlSade(s[2]), 4, kucuk),
                      hucre(tlSade(s[3]), 5, kucuk),
                      hucre(tlSade(s[4]), 5, kucuk),
                    ],
                  ),
                );
              },
            ),
          ),
          const Padding(
            padding: EdgeInsets.all(8),
            child: Text('Tutarlar TL', style: kucuk),
          ),
        ],
      ),
    );
  }
}
