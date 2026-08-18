import SwiftUI

// エージェント状態グリフ（自作アイコン。形状の正はこのファイルで、SwiftUI `Path` を直接組む）。
// viewBox は 0 0 10 10。`size` を受け `k = size / 10` で全座標・stroke 幅・dash 長を point 空間へ
// 乗算して直接構築する（`scaleEffect` は stroke をぼかすため使わない）。色は `Kind` から状態色を
// 一意に解決する（反転面では呼び出し側が対テーマ色を上書きする）。
// working=spin1.6 / waiting=float2.6(-1px)、done/idle/dormant は静止（拍は `Theme.Motion`）。
// prefers-reduced-motion 時はモーションを止め、静的な形（半分ほどの弧・吹き出し）で残す。

// MARK: - Path 生成（このファイルの座標データが形状の正）

/// 4 状態グリフの `Path` を viewBox 0..10 座標で組む（`k = size / 10` 乗算済み）。
enum StatusGlyphShape {
  /// working: `<circle cx=5 cy=5 r=3.5>` を dash [6 12]・round cap で stroke（半分ほどの弧が現れる）。
  static func workingRing(size: CGFloat) -> Path {
    circle(cx: 5, cy: 5, r: 3.5, size: size)
  }

  /// viewBox 座標の真円（`k = size / 10` 乗算）。
  private static func circle(cx: CGFloat, cy: CGFloat, r: CGFloat, size: CGFloat) -> Path {
    let k = size / 10
    let d = 2 * r * k
    return Path(ellipseIn: CGRect(x: (cx - r) * k, y: (cy - r) * k, width: d, height: d))
  }

  /// done（塗り）: 角丸四角 `<rect x1 y1 w8 h8 rx1.5>`。
  static func doneSquare(size: CGFloat) -> Path {
    let k = size / 10
    return Path(
      roundedRect: CGRect(x: 1 * k, y: 1 * k, width: 8 * k, height: 8 * k), cornerRadius: 1.5 * k)
  }

  /// done（check 線）: `<path M2.8 5.2 L4.4 6.8 L7.4 3.4>`。checkStroke 色・round・opacity .7 で stroke。
  static func doneCheck(size: CGFloat) -> Path {
    let k = size / 10
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
    var path = Path()
    path.move(to: p(2.8, 5.2))
    path.addLine(to: p(4.4, 6.8))
    path.addLine(to: p(7.4, 3.4))
    return path
  }

  /// waiting（塗り）: 角丸 r1 の吹き出し＋左下の尻尾。四隅は接線円弧で移植（尻尾は角なし）。
  /// `M1.4 2 H8.6 A..9.6 3 V6 A..8.6 7 H4.6 L3 8.8 V7 H1.4 A..0.4 6 V3 A..1.4 2 Z`
  static func bubble(size: CGFloat) -> Path {
    let k = size / 10
    func p(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: x * k, y: y * k) }
    let r = 1 * k
    var path = Path()
    path.move(to: p(1.4, 2))
    path.addArc(tangent1End: p(9.6, 2), tangent2End: p(9.6, 7), radius: r)  // 右上角丸
    path.addArc(tangent1End: p(9.6, 7), tangent2End: p(0.4, 7), radius: r)  // 右下角丸→下辺へ
    path.addLine(to: p(4.6, 7))  // 下辺
    path.addLine(to: p(3, 8.8))  // 尻尾の先（角なし）
    path.addLine(to: p(3, 7))  // 尻尾戻り
    path.addArc(tangent1End: p(0.4, 7), tangent2End: p(0.4, 2), radius: r)  // 左下角丸
    path.addArc(tangent1End: p(0.4, 2), tangent2End: p(9.6, 2), radius: r)  // 左上角丸
    path.closeSubpath()
    return path
  }

  /// idle/dormant: 積み上げた "zzz"（大/中/小の折れ線 z を各々の stroke 幅で描く）。
  /// 各 z は `M.. H.. L.. H..` の折れ線で、塗りなし・round cap/join。
  static func zzz(size: CGFloat) -> [(path: Path, width: CGFloat)] {
    let k = size / 10
    func z(_ pts: [(CGFloat, CGFloat)]) -> Path {
      var path = Path()
      path.move(to: CGPoint(x: pts[0].0 * k, y: pts[0].1 * k))
      for pt in pts.dropFirst() { path.addLine(to: CGPoint(x: pt.0 * k, y: pt.1 * k)) }
      return path
    }
    return [
      (z([(0.8, 4.6), (4.2, 4.6), (0.8, 8.4), (4.2, 8.4)]), 1.1 * k),  // 大 z
      (z([(5, 2.4), (7.4, 2.4), (5, 5.2), (7.4, 5.2)]), 0.9 * k),  // 中 z
      (z([(7.9, 0.6), (9.6, 0.6), (7.9, 2.6), (9.6, 2.6)]), 0.75 * k),  // 小 z
    ]
  }
}

// MARK: - 単一グリフ view

/// 単一の状態グリフ。`Kind`→Path/色/モーションを 1 箇所で解決する純 SwiftUI 実装。
/// 反転面（選択タブ）では `color`（対テーマ状態色）と `checkStroke` を呼び出し側が上書きする。
struct StatusGlyphView: View {
  let kind: AgentStateIcon.Kind
  var size: CGFloat = 12
  var workingStroke: CGFloat = 1.4
  var color: Color?
  var checkStroke: Color?
  /// 状態を上書きする SF Symbol 名（nil＝既定の Glass グリフ）。tint は状態色（`resolvedColor`）。
  /// 上書きの解決は呼び出し側（`AgentIconResolver` 経由の chrome 3 面）が担い、装飾用途は nil で素通し。
  var symbol: String?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  private var k: CGFloat { size / 10 }

  var body: some View {
    glyph.frame(width: size, height: size)
  }

  /// content を選び（symbol なら SF Symbol Image・nil なら Glass Path）状態モーションで包む。
  /// working=spin / waiting=float を Glass・Symbol 双方へ一律に適用する（状態モーションの唯一の出所）。
  @ViewBuilder private var glyph: some View {
    if let symbol {
      stateMotion {
        Image(systemName: symbol)
          .resizable()
          .scaledToFit()
          .frame(width: size, height: size)
          .foregroundStyle(resolvedColor)
      }
    } else {
      stateMotion { glassGlyph }
    }
  }

  /// 状態モーションの共有ラッパ。working は spin・waiting は float、それ以外（done/idle/dormant）と
  /// reduce-motion 時は静止（content 素通し）。回転角/浮遊量は body 再評価と独立に context.date から都度
  /// 算出する（chrome 再評価で凍らない）。Glass Path も SF Symbol Image もここを通す。
  @ViewBuilder private func stateMotion(@ViewBuilder _ content: () -> some View) -> some View {
    let inner = content()
    switch kind {
    case .working where !reduceMotion:
      TimelineView(.animation) { context in
        let t = context.date.timeIntervalSinceReferenceDate
        let angle = t.truncatingRemainder(dividingBy: Theme.Motion.spin) / Theme.Motion.spin * 360
        inner.rotationEffect(.degrees(angle))
      }
    case .waiting where !reduceMotion:
      // 半周期 ease の autoreverse を全周期 cos 往復（正弦イージング）で近似する。
      TimelineView(.animation) { context in
        let t = context.date.timeIntervalSinceReferenceDate
        let cycle = t.truncatingRemainder(dividingBy: Theme.Motion.float) / Theme.Motion.float
        let phase = (1 - cos(cycle * 2 * .pi)) / 2
        inner.offset(y: Theme.Motion.floatOffset * CGFloat(phase))
      }
    default:
      inner
    }
  }

  /// 既定の Glass グリフ（`StatusGlyphShape` の座標データ）。モーションは持たず `stateMotion` が包む。
  @ViewBuilder private var glassGlyph: some View {
    switch kind {
    case .working:
      StatusGlyphShape.workingRing(size: size)
        .stroke(
          resolvedColor,
          style: StrokeStyle(lineWidth: workingStroke * k, lineCap: .round, dash: [6 * k, 12 * k]))
    case .waiting:
      StatusGlyphShape.bubble(size: size).fill(resolvedColor)
    case .done:
      ZStack {
        StatusGlyphShape.doneSquare(size: size).fill(resolvedColor)
        StatusGlyphShape.doneCheck(size: size)
          .stroke(
            checkStroke ?? Color.theme.checkStroke,
            style: StrokeStyle(lineWidth: 1.3 * k, lineCap: .round, lineJoin: .round)
          )
          .opacity(0.7)
      }
    case .idle, .dormant:
      ZStack {
        ForEach(Array(StatusGlyphShape.zzz(size: size).enumerated()), id: \.offset) { _, z in
          z.path.stroke(
            resolvedColor,
            style: StrokeStyle(lineWidth: z.width, lineCap: .round, lineJoin: .round))
        }
      }
    }
  }

  /// 上書きがなければ種別→状態色（色の SSOT は `Kind.stateColor`）。
  private var resolvedColor: Color { color ?? kind.stateColor }
}

// MARK: - 状態色・セグメント（ストリップ/カラム描画の共有基盤）

extension AgentStateIcon.Kind {
  /// 種別→状態色（色の SSOT。グリフ・件数が参照する）。
  var stateColor: Color {
    switch self {
    case .working: return .theme.stateWorking
    case .waiting: return .theme.stateWaiting
    case .done: return .theme.stateDone
    case .idle: return .theme.stateIdle
    case .dormant: return .theme.stateDormant
    }
  }

  /// 反転面（選択タブ）上の状態色＝対テーマの状態色。idle/dormant はタブに出ないため通常色のまま。
  var inverseColor: Color {
    switch self {
    case .working: return .theme.stateWorkingInverse
    case .waiting: return .theme.stateWaitingInverse
    case .done: return .theme.stateDoneInverse
    case .idle, .dormant: return stateColor
    }
  }
}

/// ロールアップ描画の 1 セグメント（状態は既知・件数 > 0）。`id` は状態文字列（ロールアップ内で一意）。
struct StatusSegment: Identifiable {
  let state: String
  let kind: AgentStateIcon.Kind
  let count: Int
  var id: String { state }
}

/// 件数 > 0 かつ既知状態のセグメントだけを、呼び出し側の順序で残す。
func statusSegments(_ rollup: [(state: String, count: Int)]) -> [StatusSegment] {
  rollup.compactMap { item in
    guard item.count > 0, let kind = AgentStateIcon.kind(state: item.state) else { return nil }
    return StatusSegment(state: item.state, kind: kind, count: item.count)
  }
}

// MARK: - ステータスストリップ（chrome TopBar 右端）

/// 横断ステータスストリップ（グリフ＋数字のみ）。件数 0／未知状態は飛ばす。
/// 項目=グリフ(13px 状態色)＋gap6＋件数(mono11.5・`statusText`)、項目間 gap14・仕切り線なし。
/// 休止（idle）項目のみ opacity 0.55 で減光する。
///
/// `onTapState` を渡すと項目ごとに押せるようになる（chrome TopBar の入口）。表示専用の場所
/// （workspace パレットの集計表）は渡さないので、当たり判定もホバーも持たない見た目のまま。
struct StatusRollupView: View {
  let rollup: [(state: String, count: Int)]
  var glyphSize: CGFloat = 13
  /// 状態バッジのクリック（引数は状態文字列）。nil なら表示専用。
  var onTapState: ((String) -> Void)?
  @Environment(\.agentIconResolver) private var iconResolver

  /// 押せるときに項目の**間**へ足す当たり幅。項目間隔 14 を隣り合う項目が 7 ずつ分け合う形にして、
  /// 見た目の間隔を変えずに裸のグリフ列へ当たり判定を敷く。ストリップの両端には足さない
  /// ——外形を表示専用のときと同じに保ち、左隣の窓ドラッグ面をタップ領域で削らないため。
  private static let hitPad: CGFloat = 7

  var body: some View {
    let interactive = onTapState != nil
    let segments = statusSegments(rollup)
    HStack(spacing: interactive ? 0 : 14) {
      ForEach(Array(segments.enumerated()), id: \.element.id) { index, seg in
        StatusRollupSegment(
          segment: seg, glyphSize: glyphSize, symbol: iconResolver.symbol(for: seg.kind),
          leadPad: interactive && index > 0 ? Self.hitPad : 0,
          trailPad: interactive && index < segments.count - 1 ? Self.hitPad : 0,
          onTap: onTapState)
      }
    }
    .tracking(Theme.Typography.trackingStatus)
  }
}

/// ストリップの 1 項目。押せるとき（`onTap` 非 nil）だけ当たり領域とホバーの地を持つ。
/// ホバーの地は `＋`（新規タブ）と同じ `tabSegBg`・radius xs——chrome で「押せる」を示す既存の形。
/// 休止の減光はホバー中も保つ（押せることと状態の重みは別の話）。
private struct StatusRollupSegment: View {
  let segment: StatusSegment
  let glyphSize: CGFloat
  let symbol: String?
  let leadPad: CGFloat
  let trailPad: CGFloat
  let onTap: ((String) -> Void)?
  @State private var hovering = false

  var body: some View {
    HStack(spacing: 6) {
      StatusGlyphView(kind: segment.kind, size: glyphSize, symbol: symbol)
      Text("\(segment.count)")
        .font(.system(size: 11.5, weight: .regular, design: .monospaced))
        .foregroundStyle(Color.theme.statusText)
    }
    .opacity(segment.kind == .idle ? 0.55 : 1)
    .padding(.leading, leadPad)
    .padding(.trailing, trailPad)
    .padding(.vertical, 2)
    .background(
      RoundedRectangle(cornerRadius: Theme.Radius.xs)
        .fill(hovering ? Color.theme.tabSegBg : Color.clear)
    )
    .contentShape(Rectangle())
    .onTapGesture { onTap?(segment.state) }
    .onHover { hovering = $0 }
    // 表示専用（workspace パレットの集計表）では hit test ごと通す——当たり判定を残すと、
    // ストリップの上だけ行のタップが死ぬ。
    .allowsHitTesting(onTap != nil)
  }
}

#if DEBUG
  #Preview("StatusGlyph — 4 states + motion") {
    VStack(alignment: .leading, spacing: Theme.Space.bar) {
      HStack(spacing: Theme.Space.span) {
        ForEach(
          [AgentStateIcon.Kind.working, .waiting, .done, .idle], id: \.self
        ) { kind in
          VStack(spacing: Theme.Space.note) {
            StatusGlyphView(kind: kind, size: 24)
            StatusGlyphView(kind: kind, size: 12)
          }
        }
      }
      // タイトルバー集計（仕切り線なし・間隔化・休止は減光）
      StatusRollupView(rollup: [("working", 3), ("waiting", 1), ("done", 5), ("idle", 2)])
    }
    .padding(Theme.Space.phrase)
    .background(Color.theme.bgBase)
  }
#endif
