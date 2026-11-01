import Foundation

// The node's edits and constructors: an edit returns new nodes and shares the untouched ones, and every
// branch is balanced as it is built. Apart from `Rope.swift` so the node's type body stays under 300 lines.
extension RopeNode {
    // MARK: - Mutations (return new nodes)

    func inserting(_ bytes: Data, at offset: Int) -> RopeNode {
        switch self {
            case .leaf(let leaf):
                var data = leaf.data
                data.insert(contentsOf: bytes, at: offset)
                return RopeNode.fromLeafData(data)
            case .branch(let branch):
                let leftCount = branch.left.byteCount
                guard offset <= leftCount else {
                    let newRight = branch.right.inserting(bytes, at: offset - leftCount)
                    return RopeNode.join(branch.left, newRight)
                }
                let newLeft = branch.left.inserting(bytes, at: offset)
                return RopeNode.join(newLeft, branch.right)
        }
    }

    func removing(_ range: Range<Int>) -> RopeNode {
        if range.isEmpty { return self }
        if range.lowerBound <= 0, range.upperBound >= byteCount {
            return .leaf(LeafNode(data: Data(), newlineCount: 0))
        }
        switch self {
            case .leaf(let leaf):
                var data = leaf.data
                let lower = max(0, range.lowerBound)
                let upper = min(data.count, range.upperBound)
                if lower < upper {
                    data.removeSubrange(lower ..< upper)
                }
                return RopeNode.fromLeafData(data)
            case .branch(let branch):
                let leftCount = branch.left.byteCount
                let leftUpper = min(leftCount, range.upperBound)
                let newLeft: RopeNode
                if range.lowerBound < leftUpper {
                    newLeft = branch.left.removing(range.lowerBound ..< leftUpper)
                } else {
                    newLeft = branch.left
                }
                let newRight: RopeNode
                if range.upperBound > leftCount {
                    let rightLower = max(0, range.lowerBound - leftCount)
                    let rightUpper = range.upperBound - leftCount
                    newRight = branch.right.removing(rightLower ..< rightUpper)
                } else {
                    newRight = branch.right
                }
                return RopeNode.mergeOrBranch(newLeft, newRight)
        }
    }

    // MARK: - Constructors

    static func fromLeafData(_ data: Data) -> RopeNode {
        if data.count <= Rope.maxLeafSize {
            return makeLeaf(data)
        }
        return splitLargeLeaf(data, in: 0 ..< data.count)
    }

    private static func splitLargeLeaf(_ data: Data, in range: Range<Int>) -> RopeNode {
        if range.count <= Rope.maxLeafSize {
            return makeLeaf(data.subdata(in: range))
        }
        let mid = range.lowerBound + range.count / 2
        return makeBranch(
            splitLargeLeaf(data, in: range.lowerBound ..< mid),
            splitLargeLeaf(data, in: mid ..< range.upperBound)
        )
    }

    static func makeLeaf(_ data: Data) -> RopeNode {
        .leaf(LeafNode(data: data, newlineCount: Rope.countNewlines(in: data)))
    }

    /// Combine two subtrees, collapsing empty leaves and merging tiny adjacent
    /// leaves so the tree doesn't accumulate dead structure after deletes.
    static func mergeOrBranch(_ left: RopeNode, _ right: RopeNode) -> RopeNode {
        if case .leaf(let l) = left, l.data.isEmpty { return right }
        if case .leaf(let r) = right, r.data.isEmpty { return left }
        if case .leaf(let l) = left, case .leaf(let r) = right,
            l.data.count + r.data.count <= Rope.maxLeafSize
        {
            return makeLeaf(l.data + r.data)
        }
        return join(left, right)
    }

    /// Joins AVL subtrees whose heights can differ by more than one after an edit.
    static func join(_ left: RopeNode, _ right: RopeNode) -> RopeNode {
        if case .leaf(let leaf) = left, leaf.data.isEmpty { return right }
        if case .leaf(let leaf) = right, leaf.data.isEmpty { return left }
        if left.height > right.height + 1, case .branch(let branch) = left {
            return balance(branch.left, join(branch.right, right))
        }
        if right.height > left.height + 1, case .branch(let branch) = right {
            return balance(join(left, branch.left), branch.right)
        }
        return makeBranch(left, right)
    }

    private static func balance(_ left: RopeNode, _ right: RopeNode) -> RopeNode {
        if left.height > right.height + 1, case .branch(let branch) = left {
            if branch.left.height >= branch.right.height {
                return makeBranch(branch.left, makeBranch(branch.right, right))
            }
            if case .branch(let middle) = branch.right {
                return makeBranch(
                    makeBranch(branch.left, middle.left),
                    makeBranch(middle.right, right)
                )
            }
        }
        if right.height > left.height + 1, case .branch(let branch) = right {
            if branch.right.height >= branch.left.height {
                return makeBranch(makeBranch(left, branch.left), branch.right)
            }
            if case .branch(let middle) = branch.left {
                return makeBranch(
                    makeBranch(left, middle.left),
                    makeBranch(middle.right, branch.right)
                )
            }
        }
        return makeBranch(left, right)
    }

    static func makeBranch(_ left: RopeNode, _ right: RopeNode) -> RopeNode {
        if case .leaf(let l) = left, l.data.isEmpty { return right }
        if case .leaf(let r) = right, r.data.isEmpty { return left }
        return .branch(BranchNode(left: left, right: right))
    }
}
