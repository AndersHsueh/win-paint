import AppKit
import SwiftUI

/// 右侧浮动图层面板。对应 Windows 画图的「层」面板:
/// 浮在画布右上方的白色圆角卡片,顶部一个 ⊕ 新建按钮,下面是缩略图列表(顶层在前)。
struct LayerPanelView: View {
    let document: PaintDocument

    var body: some View {
        VStack(spacing: 0) {
            // 新建图层
            Button {
                document.addLayer()
            } label: {
                WIIconView(icon: .add, size: 18)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("新建图层")
            .padding(.top, 12)

            Divider()
                .padding(.top, 10)

            ScrollView {
                VStack(spacing: 12) {
                    // 顶层在前
                    ForEach(Array(document.layers.indices.reversed()), id: \.self) { index in
                        layerRow(index)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 12)
            }

            Spacer(minLength: 0)
        }
        .frame(width: 139)
        .frame(height: 655)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(WIPaint.paper)
                .shadow(color: .black.opacity(0.20), radius: 9, x: 0, y: 2)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.black.opacity(0.09), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func layerRow(_ index: Int) -> some View {
        let layer = document.layers[index]
        let isSelected = document.selectedLayerIndex == index

        VStack(spacing: 4) {
            ZStack(alignment: .topTrailing) {
                // 缩略图
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .strokeBorder(isSelected ? WIPaint.accent : Color.black.opacity(0.18),
                                          lineWidth: isSelected ? 2 : 1)
                    )
                    .overlay {
                        if let thumb = layer.thumbnail() {
                            Image(nsImage: NSImage(cgImage: thumb, size: NSSize(width: thumb.width, height: thumb.height)))
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                                .padding(2)
                        }
                    }
                    .frame(width: 108, height: 76)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        document.selectLayer(index)
                    }
                    .contextMenu {
                        Button("上移一层") {
                            document.moveLayer(from: index, to: min(index + 1, document.layers.count - 1))
                        }
                        Button("下移一层") {
                            document.moveLayer(from: index, to: max(index - 1, 0))
                        }
                        Divider()
                        Button("删除图层", role: .destructive) {
                            document.deleteLayer(at: index)
                        }
                        .disabled(document.layers.count <= 1)
                    }

                // 显隐开关
                Button {
                    document.setLayerVisible(index, !layer.isVisible)
                } label: {
                    Image(systemName: layer.isVisible ? "eye.fill" : "eye.slash.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(Color.secondary)
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: -4)
            }

            Text(layer.name)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? WIPaint.ink : Color.secondary)
                .lineLimit(1)
                .frame(width: 108)
        }
    }
}
