## `pull_request`

| Webhook event payload                                                   | Activity types                                                                                                                                                                                                                                                                                                                                                                                                                   | `GITHUB_SHA`                                 | `GITHUB_REF`                                          |
| ----------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- | ----------------------------------------------------- |
| [`pull_request`](/en/webhooks/webhook-events-and-payloads#pull_request) | - `assigned`<br/>- `unassigned`<br/>- `labeled`<br/>- `unlabeled`<br/>- `opened`<br/>- `edited`<br/>- `closed`<br/>- `reopened`<br/>- `synchronize`<br/>- `converted_to_draft`<br/>- `locked`<br/>- `unlocked`<br/>- `enqueued`<br/>- `dequeued`<br/>- `milestoned`<br/>- `demilestoned`<br/>- `ready_for_review`<br/>- `review_requested`<br/>- `review_request_removed`<br/>- `auto_merge_enabled`<br/>- `auto_merge_disabled` | Last merge commit on the `GITHUB_REF` branch | PR merge branch `refs/pull/PULL_REQUEST_NUMBER/merge` |

> [!NOTE]
>
> * More than one activity type triggers this event. For information about each activity type, see [Webhook events and payloads](/en/webhooks/webhook-events-and-payloads#pull_request). By default, a workflow only runs when a `pull_request` event's activity type is `opened`, `synchronize`, or `reopened`. To trigger workflows by different activity types, use the `types` keyword. For more information, see [Workflow syntax for GitHub Actions](/en/actions/reference/workflows-and-actions/workflow-syntax#onevent_nametypes).
> * Workflows will not run on `pull_request` activity if the pull request has a merge conflict. The merge conflict must be resolved first. Conversely, workflows with the `pull_request_target` event will run even if the pull request has a merge conflict. Before using the `pull_request_target` trigger, you should be aware of the security risks. For more information, see [`pull_request_target`](#pull_request_target).
> * The `pull_request` webhook event payload is empty for merged pull requests and pull requests that come from forked repositories.
> * When a pull request is created or updated by a workflow using `GITHUB_TOKEN`, `pull_request` events with the `opened`, `synchronize`, or `reopened` activity types create workflow runs that require approval. A user with write access to the repository can approve these runs from the pull request page. With the exception of `workflow_dispatch` and `repository_dispatch`, other `GITHUB_TOKEN`-triggered events do not create workflow runs at all.
> * The value of `GITHUB_REF` varies for a closed pull request depending on whether the pull request has been merged or not. If a pull request was closed but not merged, it will be `refs/pull/PULL_REQUEST_NUMBER/merge`. If a pull request was closed as a result of being merged, it will be the fully qualified `ref` of the branch it was merged into, for example `/refs/heads/main`.

Runs your workflow when activity on a pull request in the workflow's repository occurs. For example, if no activity types are specified, the workflow runs when a pull request is opened or reopened or when the head branch of the pull request is updated. For activity related to pull request reviews, pull request review comments, or pull request comments, use the [`pull_request_review`](#pull_request_review), [`pull_request_review_comment`](#pull_request_review_comment), or [`issue_comment`](#issue_comment) events instead. For information about the pull request APIs, see [Pull requests](/en/graphql/reference/pulls#object-pullrequest) in the GraphQL API documentation or [REST API endpoints for pull requests](/en/rest/pulls).

Note that `GITHUB_SHA` for this event is the last merge commit of the pull request merge branch. If you want to get the commit ID for the last commit to the head branch of the pull request, use `github.event.pull_request.head.sha` instead. For more information about merge branches, see [Pull requests](/en/pull-requests/reference/pull-requests#pull-request-refs-and-merge-branches).

### How the merge branch affects your workflow

For open, mergeable pull requests, workflows triggered by the `pull_request` event set `GITHUB_REF` to the merge branch. Because `actions/checkout` uses `GITHUB_REF` by default, it checks out the merge branch. Your CI tests run against the merged result, not just the head branch alone:

* `GITHUB_REF` is set to `refs/pull/PULL_REQUEST_NUMBER/merge`
* `GITHUB_SHA` is the SHA of the merge commit on the merge branch

To test only the head branch commits without simulating a merge, check out the head branch using `github.event.pull_request.head.sha` in your workflow.

For example, you can run a workflow when a pull request has been opened or reopened.

```yaml
on:
  pull_request:
    types: [opened, reopened]
```

You can use the event context to further control when jobs in your workflow will run. For example, this workflow will run when a review is requested on a pull request, but the `specific_review_requested` job will only run when a review by `octo-team` is requested.

```yaml
on:
  pull_request:
    types: [review_requested]
jobs:
  specific_review_requested:
    runs-on: ubuntu-latest
    if: ${{ github.event.requested_team.name == 'octo-team'}}
    steps:
      - run: echo 'A review from octo-team was requested'
```

