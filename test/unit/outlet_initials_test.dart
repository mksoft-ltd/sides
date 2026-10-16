import 'package:flutter_test/flutter_test.dart';
import 'package:sides/shared/widgets/outlet_avatar.dart';

void main() {
  test('outlet initials: acronyms as is, else two initials, never a logo', () {
    expect(outletInitials('BBC News'), 'BBC');
    expect(outletInitials('NBC News'), 'NBC');
    expect(outletInitials('CGTN'), 'CGT');
    expect(outletInitials('The New York Times'), 'NYT');
    expect(outletInitials('New York Post'), 'NYP');
    expect(outletInitials('South China Morning Post'), 'SCM');
    expect(outletInitials('Fox News'), 'FN');
    expect(outletInitials('The Guardian'), 'GU');
    expect(outletInitials('Axios'), 'AX');
    expect(outletInitials('The National (UAE)'), 'NU');
    expect(outletInitials('Al Jazeera English'), 'AJE');
    expect(outletInitials('France 24'), 'F2');
    expect(outletInitials(''), '?');
  });
}
