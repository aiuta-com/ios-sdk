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

import Kingfisher
import Resolver
import UIKit

@_spi(Aiuta) public final class UrlFetcher: BaseFetcher {
    private var downloadTask: DownloadTask?
    private let fetcher = KingfisherManager.shared

    public init(_ string: String, quality: ImageQuality, isRounded: Bool = false) {
        super.init()
        guard let url = URL(string: string) else {
            onImage.fire(nil)
            return
        }

        load(url, quality: quality, isRounded: isRounded)
    }

    public init(_ url: URL, quality: ImageQuality, isRounded: Bool = false) {
        super.init()
        load(url, quality: quality, isRounded: isRounded)
    }
}

private extension UrlFetcher {
    func load(_ url: URL, quality: ImageQuality, isRounded: Bool = false) {
        var options: KingfisherOptionsInfo = [
            .retryStrategy(DelayRetryStrategy(maxRetryCount: 3, retryInterval: .accumulated(1))),
            .processor(DownsamplingImageProcessor(size: .init(square: imageTraits.largestSize(for: quality)))),
            .backgroundDecode,
        ]

        if isRounded {
            options.append(.processor(RoundCornerImageProcessor(radius: .heightFraction(0.5))))
        }

        downloadTask = fetcher.retrieveImage(with: url, options: options) { [weak self] result in
            self?.downloadTask = nil
            switch result {
                case let .success(result):
                    self?.onImage.fire(result.image)
                case let .failure(error):
                    trace(i: "x", "Failed to fetch", url.absoluteString, error.localizedDescription)
                    self?.onImage.fire(nil)
            }
        }
    }
}
