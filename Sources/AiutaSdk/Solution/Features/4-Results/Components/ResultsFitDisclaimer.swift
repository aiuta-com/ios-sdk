// Copyright 2024 Aiuta USA, Inc
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//      http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

@_spi(Aiuta) import AiutaKit
import UIKit

extension ResultsView {
    final class FitDisclaimer: Stroke {
        let button = FitButton()

        override func setup() {
            color = ds.color.neutral
            view.isVisible = ds.config.behavior.showFitDisclaimerOnResults
        }

        override func updateLayout() {
            layout.make { make in
                make.height = 80
                make.leftRight = 0
                make.radius = ds.dimensions.bottomSheetRadius
            }
        }
    }

    final class FitButton: PlainButton {
        let label = Label { it, ds in
            it.font = ds.font.description
            it.color = ds.color.primary
            it.text = L.fitDisclaimerTitle
        }

        let icon = Image { it, ds in
            it.isAutoSize = false
            it.tint = ds.color.primary
            it.image = ds.image.icon20(.info)
        }

        override func updateLayout() {
            layout.make { make in
                make.leftRight = 0
                make.height = 27
            }

            label.layout.make { make in
                make.centerX = icon.hasImage ? -12 : 0
                make.centerY = -1
            }

            icon.layout.make { make in
                make.square = 20
                make.left = label.layout.rightPin + 4
                make.centerY = -1
            }
        }
    }
}
