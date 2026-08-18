import SwiftUI

/// ⌘⌘（前面時）/ TopBar ストリップで開く Attention パレットの状態機械。
///
/// 全ライブペインの agentState（waiting/done/working）を stateChangedAt 降順にフラット一覧し、
/// ↑↓ で選択・Enter/行タップでそのペインへ移動（WS activate＋タブ選択＋ペイン focus）・
/// Esc/scrim で閉じる。フィルタ入力欄・ドリルインは持たない。空のときは情報行 1 本。
/// ヘッダは breadcrumb「attention」＋右端 `⌘⌘` バッジ（デザイン第10シーン）。
///
/// 状態で絞った一覧（TopBar の状態バッジから開く）だけは `filter` を持つ。絞りを決めるのは
/// **入口だけ**で、カードの中に絞り込みを操作する面は持たない——押したバッジがそのまま一覧の
/// 見出しになる形にして、覚える操作を増やさない。
///
/// 描画は `PaletteOverlay`/`PaletteCard`。行の中身は `AttentionRowView`（customContent）。
/// 表示中の更新は提示元（WindowController）が `flushChrome` の snapshot 更新時に `setRows` で流し込む。
@Observable final class AttentionPaletteModel {
  var onFocusPane: ((Int) -> Void)?
  var onDismiss: (() -> Void)?

  /// 入口が決めた絞り込み（nil＝絞り込みなし＝⌘⌘ で開いた一覧）。開いている間は変わらない
  /// ——別の状態へ移るときはカードごと立て直す（見た目は同じ面でも中身は別の一覧なので、
  /// 選択も引き継がない）。
  let filter: AgentStateIcon.Kind?

  let render = PaletteModel()
  /// `filter` で絞った後の行。錨（paneId）もこの絞り込み後の並びで取る。
  private var rows: [AttentionRow] = []
  private let localization: LocalizationStore

  init(
    localization: LocalizationStore = LocalizationStore(language: .systemDefault),
    filter: AgentStateIcon.Kind? = nil
  ) {
    self.localization = localization
    self.filter = filter
    render.breadcrumb = filter.map { "attention › " + $0.label(localization) } ?? "attention"
    // ⌘⌘ で開けるのは絞り込みなしの一覧だけ。絞った一覧に載せると到達手段の嘘になる。
    render.headerPills =
      filter == nil ? [PaletteModel.HeaderPill(label: "⌘⌘", active: false)] : []
    render.surface = .popup  // デザイン第10シーン rgba(panel, 0.9)＝popup 級の面（枠・幾何は panel 級）
    render.scrimStrength = .normal  // 頻繁に開く軽いパレット（workspace 切替と同じ通常暗幕）
    render.hintKeys = [
      PaletteModel.HintKey(key: "↵", label: localization.string(.attentionHintJump)),
      PaletteModel.HintKey(key: "↑↓", label: localization.string(.attentionHintSelect)),
      PaletteModel.HintKey(key: "esc", label: localization.string(.attentionHintClose)),
    ]
    render.onScrimTap = { [weak self] in self?.onDismiss?() }
    render.onTapRow = { [weak self] i in
      self?.render.selected = i
      self?.activate()
    }
    render.onUp = { [weak self] in self?.render.move(-1) }
    render.onDown = { [weak self] in self?.render.move(1) }
    render.onJumpTop = { [weak self] in self?.render.jump(-1) }
    render.onJumpBottom = { [weak self] in self?.render.jump(1) }
    render.onActivate = { [weak self] in self?.activate() }
    render.onEscape = { [weak self] in self?.onDismiss?() }
    rebuild()
  }

  /// キー操作を受けるため focusToken を進めて first responder を確定させる。
  func focus() { render.focus() }

  /// snapshot を反映して再描画する（開いたまま届く report の追従にも使う）。
  ///
  /// 並びは stateChangedAt 降順なので、開いている間に別ペインが waiting / done へ変われば行が
  /// 先頭に挿し込まれ、以降の index が 1 つずつずれる。index を据え置くと ↵ が**選んだ覚えの
  /// ない別ペイン**へ飛ぶので、選択は paneId を錨に追い直す（→ `ModalSelection.restore`。
  /// 裏の更新はユーザの意図ではないのでモダリティは奪わない）。錨が消えたときだけ範囲へ丸める。
  func setRows(_ rows: [AttentionRow]) {
    // 絞り込みは錨を探す**前**に効かせる——`self.rows` を常に絞り込み後で揃えないと、
    // 錨の取得と探索が違う並びを見て選択が飛ぶ。絞りから外れた行が消えるのは
    // 「一覧から消えた」と同じ扱いで、既存の clamp 経路がそのまま拾う。
    let visible = filter.map { f in rows.filter { $0.state == f.state } } ?? rows
    let anchor =
      self.rows.indices.contains(render.selected) ? self.rows[render.selected].paneId : nil
    self.rows = visible
    rebuild()
    if let anchor, let i = visible.firstIndex(where: { $0.paneId == anchor }) {
      render.restoreSelection(i)
      return
    }
    render.clampSelection()
  }

  // MARK: - 操作の意味（キー意図とテストの両方がここを駆動する）

  func activate() {
    guard rows.indices.contains(render.selected) else { return }
    onFocusPane?(rows[render.selected].paneId)
  }

  private func rebuild() {
    render.rows =
      rows.isEmpty
      ? [PaletteModel.RowItem(label: localization.string(.attentionEmpty), enabled: false)]
      : rows.map { row in
        PaletteModel.RowItem(
          label: "\(row.workspaceName) › \(row.tabTitle)",
          customContent: AnyView(AttentionRowView(row: row)))
      }
  }
}
