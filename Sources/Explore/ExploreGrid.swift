// Overview: Explore: grid metrics, tile layout and scrolling.
import UIKit
import Foundation
import AVFoundation
import CoreMedia
import AudioToolbox
import MediaPlayer
import Security
import QuartzCore
import CoreText
import ImageIO
import SystemConfiguration

extension ExploreViewController {


    func gridMetrics()
        -> (
            width: CGFloat,
            spacing: CGFloat,
            tileWidth: CGFloat
        )
    {
        let width =
            max(
                1.0,
                scrollView.bounds.size.width
            )

        let spacing:
            CGFloat = 2.0

        let tileWidth =
            floor(
                (
                    width -
                    spacing * 4.0
                ) /
                3.0
            )

        return (
            width,
            spacing,
            tileWidth
        )
    }

    func frameForGridIndex(
        _ index: Int
    ) -> CGRect {
        let metrics =
            gridMetrics()

        let row =
            index / 3

        let column =
            index % 3

        return CGRect(
            x:
                metrics.spacing +
                CGFloat(column) *
                (
                    metrics.tileWidth +
                    metrics.spacing
                ),
            y:
                metrics.spacing +
                CGFloat(row) *
                (
                    metrics.tileWidth +
                    metrics.spacing
                ),
            width:
                metrics.tileWidth,
            height:
                metrics.tileWidth
        )
    }

    func layoutGrid() {
        let metrics =
            gridMetrics()

        for placeholder in
            placeholderViews
        {
            let index =
                placeholder.tag -
                placeholderTagBase

            let calculatedGridFrame = frameForGridIndex(index)

            if magnistraSavedGrid || placeholder.frame != calculatedGridFrame {

                placeholder.frame = calculatedGridFrame

            }
        }

        for tile in tiles {
            let calculatedGridFrame = frameForGridIndex(tile.postIndex)
            if magnistraSavedGrid || tile.frame != calculatedGridFrame {
                tile.frame = calculatedGridFrame
            }
        }

        let visibleCount =
            max(
                posts.count,
                placeholderViews
                    .map {
                        $0.tag -
                        placeholderTagBase +
                        1
                    }
                    .max() ?? 0
            )

        let rows =
            (
                visibleCount +
                2
            ) /
            3

        let gridHeight =
            metrics.spacing +
            CGFloat(rows) *
            (
                metrics.tileWidth +
                metrics.spacing
            )

        let footerHeight:
            CGFloat =
                paginationLabel.isHidden
                    ? 0.0
                    : 38.0

        paginationLabel.frame =
            CGRect(
                x: 0.0,
                y: gridHeight,
                width: metrics.width,
                height: footerHeight
            )

        paginationOverscrollFill.isHidden =
            paginationLabel.isHidden

        paginationOverscrollFill.frame =
            CGRect(
                x: 0.0,
                y: gridHeight + footerHeight,
                width: metrics.width,
                height: max(
                    640.0,
                    scrollView.bounds.size.height * 2.0
                )
            )

        let gridContentSize = CGSize(
                width: metrics.width,
                height:
                    max(
                        gridHeight +
                        footerHeight,
                        scrollView.bounds
                            .size.height +
                        1.0
                    )
            )
        if magnistraSavedGrid || scrollView.contentSize != gridContentSize {
            scrollView.contentSize = gridContentSize
        }
    }

    func scrollViewDidScroll(
        _ scrollView:
            UIScrollView
    ) {
        magnistraLoadNearViewportImages()
        unifiedLoadingBand.refresh()
        if !magnistraSavedGrid {
            rootTabHeaderScroll.observe(scrollView, initialContentReady: !posts.isEmpty)
        }
        if
            posts.isEmpty ||
            isLoadingPage ||
            reachedEnd
        {
            return
        }

        let remaining =
            scrollView.contentSize.height -
            (
                scrollView.contentOffset.y +
                scrollView.bounds.size.height
            )

        if
            remaining < 420.0,
            magnistraUserInitiatedPagination(scrollView),
            let cursor =
                nextMaxID,
            !cursor.isEmpty
        {
            requestPage(
                maxID: cursor,
                replacing: false
            )
        }
    }
}
