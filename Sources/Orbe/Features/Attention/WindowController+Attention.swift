import AppKit

/// Attention パレットの提示と、Attention snapshot（単一情報源 `AttentionStore`）の流し込み。
/// WindowController 本体から Attention の関心を分離する。
extension WindowController {
  /// `flushChrome` から呼ぶ snapshot 更新（既存 coalesce に相乗り。新たな走査タイミングは作らない）。
  /// パレット表示中は開いたまま行を追従させる（`reloadPalette` と同じ流儀）。
  func refreshAttentionSnapshot() {
    attentionStore.apply(rows: AttentionSnapshot.rows(of: workspaces))
    if model.overlay == .attentionPalette, let palette = model.attentionPalette {
      palette.setRows(attentionRows(filter: palette.filter))
    }
  }

  /// パレットに流す行。既定は単一情報源（`attentionStore`）をそのまま渡し、絞り込みは
  /// パレット側が効かせる。休止（idle）で絞ったときだけ builder を直接呼ぶ——idle は store に
  /// 載らない（載せるとメニューバー投影の件数・一覧・②の取り下げ判定が動く）ので、
  /// この一覧のためだけに組み直す。
  private func attentionRows(filter: AgentStateIcon.Kind?) -> [AttentionRow] {
    guard filter == .idle else { return attentionStore.rows }
    return AttentionSnapshot.rows(of: workspaces, states: [AgentStateIcon.Kind.idle.state])
  }

  /// TopBar の状態バッジのクリック。押した状態だけに絞った一覧を開く。同じ状態のバッジを
  /// もう一度押せば閉じる（開いた入口をそのまま出口にする）。⌘⌘ で開いている絞り込みなしの
  /// 一覧から押したときは、閉じずにその状態の一覧へ差し替える。
  func tapAttentionBadge(state: String) {
    guard let kind = AgentStateIcon.kind(state: state) else { return }
    if model.overlay == .attentionPalette, model.attentionPalette?.filter == kind {
      dismissPalette()
      return
    }
    showAttentionPalette(filter: kind)
  }

  /// ⌘⌘（前面時）のトグル。開いていれば閉じ、他パレット表示中は差し替える（既存パレット同士の
  /// 遷移規約）。languageSelect / onboarding / updateChanges の真のモーダル中は no-op。
  /// ヘルプ（⌘H）表示中も no-op——ヘルプはショートカットを試し押しして確かめる場で、押下は
  /// キーボード点灯と行ハイライトにのみ使う（実動作するのは ⌘H と esc だけ）。ヘルプに載る
  /// ⌘⌘ はそこで必ず試されるため、この規律から外すと試し押しでヘルプ自体が消える。
  func toggleAttentionPalette() {
    switch model.overlay {
    case .attentionPalette:
      dismissPalette()
    case .languageSelect, .onboarding, .updateChanges, .help:
      return
    case .none, .workspacePalette, .workspaceCreate, .agentPalette, .dispatchPalette,
      .settingsPalette:
      showAttentionPalette()
    }
  }

  /// Attention パレットを開く（⌘⌘＝絞り込みなし・TopBar の状態バッジ＝その状態だけ）。
  /// 同じ絞り込みで既に開いていれば再フォーカスするだけ。**違う絞り込みなら中身を立て直す**
  /// ——早期 return のままだと、開いている最中に別のバッジを押しても何も起きない。
  func showAttentionPalette(filter: AgentStateIcon.Kind? = nil) {
    if model.overlay == .attentionPalette, model.attentionPalette?.filter == filter {
      model.attentionPalette?.focus()
      return
    }
    let p = AttentionPaletteModel(localization: localization, filter: filter)
    p.onDismiss = { [weak self] in self?.dismissPalette() }
    p.onFocusPane = { [weak self] paneId in
      guard let self else { return }
      _ = self.controlFocusPane(paneId: paneId)  // WS activate＋タブ選択＋ペイン focus（既存経路を共用）
      self.dismissPalette()  // done のフォーカス消費は select() 経由で既存規律どおり効く
    }
    p.setRows(attentionRows(filter: filter))
    model.attentionPalette = p
    model.overlay = .attentionPalette
    p.focus()
    reconfirmFocusNextTick()  // 別 overlay からの遷移で去りゆくカードの teardown に勝つ
  }

  /// メニューバー②のクリック直行・行クリックが使う「そのペインへ移動」（前面化は呼び出し側）。
  func focusAttentionPane(paneId: Int) {
    _ = controlFocusPane(paneId: paneId)
  }

  /// メニューバー②（一過性の滲み出しピル）を立てる。ただし発信元ペインが**見ているタブ**に
  /// あるときは立てない——端末にその結果もプロンプトも出ている面で、注意だけを二重に奪わないため。
  /// 抑制は「立てない」だけで、既に出ているピル（別の場所で起きた変化の通知）には触らない。
  func noteAttentionTransient(for pane: SurfaceView) {
    // 抑制するのは「見ているタブが実在し、かつペインがそのタブに属する」ときだけ。visibleTab が
    // nil＝背面なら誰も見ていないので必ず立てる（controller は weak。nil 同士を一致と読ませない）。
    if let visibleTab, pane.controller === visibleTab { return }
    guard let row = attentionRow(for: pane) else { return }
    attentionStore.noteTransient(row)
  }

  /// 一過性表示（メニューバー②）用の 1 行 snapshot。発信元ペインの所属 WS・タブから組む。
  /// 対象は一覧（`AttentionSnapshot.rows`）と同じ **activate 済み workspace のライブペインのみ**
  /// ——②は一覧の投影なので、立てる側と取り下げる側が同じ集合を見る。見つからなければ nil。
  private func attentionRow(for pane: SurfaceView) -> AttentionRow? {
    for ws in workspaces where ws.activated {
      for tab in ws.tabs where tab.controlAllPanes().contains(where: { $0 === pane }) {
        guard let state = pane.agentState else { return nil }
        return AttentionRow(
          paneId: pane.id,
          workspaceName: ws.name,
          tabTitle: tab.displayTitle(workspaceRoot: ws.rootPath),
          state: state,
          message: state == "working" ? nil : pane.agentMessage?.text,
          stateChangedAt: pane.agentStateChangedAt ?? Date())
      }
    }
    return nil
  }
}
