import XCTest

@testable import Orbe

/// Attention パレットが**開いたまま**行の差し替えを受ける（`flushChrome` の snapshot 更新が
/// `setRows` で流し込む）ときの選択の扱いを固定する。並びは stateChangedAt 降順なので、
/// 表示中に別ペインが waiting / done へ変われば行は先頭へ挿し込まれ、index は総ずれする。
@MainActor
final class AttentionPaletteTests: OrbeTestCase {

  private func row(_ paneId: Int, at offset: TimeInterval, state: String = "waiting")
    -> AttentionRow
  {
    AttentionRow(
      paneId: paneId, workspaceName: "ws\(paneId)", tabTitle: "tab", state: state,
      message: nil, stateChangedAt: Date().addingTimeInterval(offset))
  }

  /// 行が先頭に挿し込まれても、選択は**同じペイン**に留まる（index を据え置かない）。
  /// これを外すと ↵ が「選んだ覚えのない別ペイン」へ飛び、その端末に打鍵が入る。
  func testSelectionFollowsPaneWhenRowsShift() {
    let model = AttentionPaletteModel()
    model.setRows([row(1, at: -10), row(2, at: -20)])
    model.render.selected = 1  // ペイン 2 を選ぶ

    // ペイン 3 が新たに waiting になり、降順で先頭へ入る（1 → index 1、2 → index 2）。
    model.setRows([row(3, at: 0), row(1, at: -10), row(2, at: -20)])
    XCTAssertEqual(model.render.selected, 2, "選択は index でなくペイン 2 に追随する")

    var focused: Int?
    model.onFocusPane = { focused = $0 }
    model.activate()
    XCTAssertEqual(focused, 2, "↵ は選んだままのペインへ飛ぶ")
  }

  /// 選択していたペインが一覧から消えたら（idle 化・clear・閉じた）範囲へ丸める。
  func testSelectionClampsWhenSelectedPaneDisappears() {
    let model = AttentionPaletteModel()
    model.setRows([row(1, at: -10), row(2, at: -20), row(3, at: -30)])
    model.render.selected = 2  // ペイン 3

    model.setRows([row(1, at: -10)])
    XCTAssertEqual(model.render.selected, 0)
  }

  // MARK: 状態で絞った一覧（TopBar の状態バッジから開く）

  /// 絞り込みは入口が決める——渡された行のうち、その状態のものだけが並ぶ。
  func testFilterKeepsOnlyItsState() {
    let model = AttentionPaletteModel(filter: .done)
    model.setRows([
      row(1, at: -10, state: "waiting"), row(2, at: -20, state: "done"),
      row(3, at: -30, state: "working"), row(4, at: -40, state: "done"),
    ])

    var focused: Int?
    model.onFocusPane = { focused = $0 }
    model.render.selected = 1
    model.activate()
    XCTAssertEqual(focused, 4, "done の 2 行だけが並ぶ（index 1 は ペイン 4）")
  }

  /// 錨の追い直しは**絞り込み後**の並びで効く。絞る前の並びで錨を取ると、
  /// ↵ が選んだ覚えのない別ペインへ飛ぶ（フィルタ無しのときと同じ事故）。
  func testFilteredSelectionFollowsPaneWhenRowsShift() {
    let model = AttentionPaletteModel(filter: .done)
    model.setRows([
      row(1, at: -10, state: "done"), row(2, at: -15, state: "waiting"),
      row(3, at: -20, state: "done"),
    ])
    model.render.selected = 1  // 絞り込み後の 2 行目 ＝ ペイン 3

    // ペイン 4 が done になって先頭へ入り、waiting も 1 枚増える（絞り込み前の並びは総ずれ）。
    model.setRows([
      row(4, at: 0, state: "done"), row(5, at: -5, state: "waiting"),
      row(1, at: -10, state: "done"), row(2, at: -15, state: "waiting"),
      row(3, at: -20, state: "done"),
    ])
    XCTAssertEqual(model.render.selected, 2, "選択は index でなくペイン 3 に追随する")

    var focused: Int?
    model.onFocusPane = { focused = $0 }
    model.activate()
    XCTAssertEqual(focused, 3)
  }

  /// 選択行が絞り込みから外れたら（状態が変わった）、一覧から消えたのと同じく範囲へ丸める。
  func testFilteredSelectionClampsWhenRowLeavesFilter() {
    let model = AttentionPaletteModel(filter: .done)
    model.setRows([
      row(1, at: -10, state: "done"), row(2, at: -20, state: "done"),
      row(3, at: -30, state: "done"),
    ])
    model.render.selected = 2  // ペイン 3

    model.setRows([
      row(1, at: -10, state: "done"), row(2, at: -20, state: "done"),
      row(3, at: -30, state: "working"),  // 選択していた行が絞り込みから外れる
    ])
    XCTAssertEqual(model.render.selected, 1)
  }

  /// 休止（idle）で絞った一覧も同じ器で並ぶ——builder が組み直した行をそのまま受ける。
  func testIdleFilterListsIdleRows() {
    let model = AttentionPaletteModel(filter: .idle)
    model.setRows([row(1, at: -10, state: "idle"), row(2, at: -20, state: "idle")])

    var focused: Int?
    model.onFocusPane = { focused = $0 }
    model.render.selected = 1
    model.activate()
    XCTAssertEqual(focused, 2)
  }

  /// `⌘⌘` バッジは絞り込みなしの一覧にだけ出す（絞った一覧に載せると到達手段の嘘になる）。
  /// breadcrumb は押した状態を見出しにする。
  func testHeaderShowsFilterAndDropsShortcutPill() {
    let l10n = LocalizationStore(language: .systemDefault)
    let plain = AttentionPaletteModel(localization: l10n)
    XCTAssertEqual(plain.render.breadcrumb, "attention")
    XCTAssertEqual(plain.render.headerPills.map(\.label), ["⌘⌘"])

    let filtered = AttentionPaletteModel(localization: l10n, filter: .done)
    XCTAssertEqual(
      filtered.render.breadcrumb, "attention › " + AgentStateIcon.Kind.done.label(l10n))
    XCTAssertTrue(filtered.render.headerPills.isEmpty)
  }

  /// 追い直しはモダリティを奪わない——ポインタ操作中に裏で行が動いても、ホバー追従が切れない。
  func testRestoreKeepsPointerModality() {
    let model = AttentionPaletteModel()
    model.setRows([row(1, at: -10), row(2, at: -20)])
    model.render.inputModality = .pointer
    model.render.hoverSelect(1)

    model.setRows([row(3, at: 0), row(1, at: -10), row(2, at: -20)])
    XCTAssertEqual(model.render.inputModality, .pointer, "裏の差し替えで .keyboard へ戻さない")
    model.render.hoverSelect(0)
    XCTAssertEqual(model.render.selected, 0, "ホバー追従が生きたまま")
  }
}
