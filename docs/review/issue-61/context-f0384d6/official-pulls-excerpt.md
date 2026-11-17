## Get a pull request

```
GET /repos/{owner}/{repo}/pulls/{pull_number}
```

Draft pull requests are available in public repositories with GitHub Free and GitHub Free for organizations, GitHub Pro, and legacy per-repository billing plans, and in public and private repositories with GitHub Team and GitHub Enterprise Cloud. For more information, see GitHub's products in the GitHub Help documentation.
Lists details of a pull request by providing its number.
When you get, create, or edit a pull request, GitHub creates a merge commit to test whether the pull request can be automatically merged into the base branch. This test commit is not added to the base branch or the head branch. You can review the status of the test commit using the mergeable key. For more information, see "Checking mergeability of pull requests".
The value of the mergeable attribute can be true, false, or null. If the value is null, then GitHub has started a background job to compute the mergeability. After giving the job time to complete, resubmit the request. When the job finishes, you will see a non-null value for the mergeable attribute in the response. If mergeable is true, then merge\_commit\_sha will be the SHA of the test merge commit.
The value of the merge\_commit\_sha attribute changes depending on the state of the pull request. Before merging a pull request, the merge\_commit\_sha attribute holds the SHA of the test merge commit. After merging a pull request, the merge\_commit\_sha attribute changes depending on how you merged the pull request:

If merged as a merge commit, merge\_commit\_sha represents the SHA of the merge commit.
If merged via a squash, merge\_commit\_sha represents the SHA of the squashed commit on the base branch.
If rebased, merge\_commit\_sha represents the commit that the base branch was updated to.

Pass the appropriate media type to fetch diff and patch formats.
This endpoint supports the following custom media types. For more information, see "Media types."

application/vnd.github.raw+json: Returns the raw markdown body. Response will include body. This is the default if you do not pass any specific media type.
application/vnd.github.text+json: Returns a text only representation of the markdown body. Response will include body\_text.
application/vnd.github.html+json: Returns HTML rendered from the body's markdown. Response will include body\_html.
application/vnd.github.full+json: Returns raw, text, and HTML representations. Response will include body, body\_text, and body\_html.
application/vnd.github.diff: For more information, see "git-diff" in the Git documentation. If a diff is corrupt, contact us through the GitHub Support portal. Include the repository name and pull request ID in your message.

