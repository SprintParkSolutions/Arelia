/**
 * @description Sends the Additional Budget Request emails whenever Additional_Request_Status__c
 * changes on a Project__c, regardless of what updated the record. Delegates the transition
 * handling and sending to ProjectAdditionalBudgetController so there is a single implementation
 * shared by every update source. Meant to be called from ProjectTrigger's after-update block.
 */
public without sharing class ProjectAdditionalBudgetTriggerHandler {

    private static final String STATUS_PENDING = 'Pending';
    private static final String STATUS_APPROVED = 'Approved';
    private static final String STATUS_REJECTED = 'Rejected';

    public static void handleAfterUpdate(List<Project__c> newList, Map<Id, Project__c> oldMap) {
        for (Project__c newProj : newList) {
            Project__c oldProj = oldMap.get(newProj.Id);
            String oldStatus = oldProj.Additional_Request_Status__c;
            String newStatus = newProj.Additional_Request_Status__c;

            if (!shouldDispatchEmail(newProj, oldProj, oldStatus, newStatus)) {
                continue;
            }

            try {
                dispatchEmail(newProj, oldProj, newStatus);
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Additional budget notification failed for ' + newProj.Id + ': ' + ex.getMessage());
            }
        }
    }

    /**
     * @description Decides whether this update should trigger a notification email.
     * Approved/Rejected are always single, complete transitions from approveRequest()/
     * rejectRequest(), so any change into those statuses is dispatched as before.
     *
     * Pending is different: the mobile app's request flow can PATCH Additional_Request_Status__c
     * = 'Pending' in one call and fill in Pending_Additional_Amount__c/Pending_Additional_Reason__c
     * in a later, separate call - so status alone never changes again once it's already 'Pending'.
     * Relying solely on "did status change" means that second call, which is the one that actually
     * completes the request, never dispatches the manager email. Instead: only dispatch a 'Pending'
     * transition once the request is actually complete (has a positive amount and a reason), and
     * also re-check on every later update while status stays 'Pending' - dispatching once the
     * pending amount/reason changed AND the request is now complete.
     */
    @TestVisible
    private static Boolean shouldDispatchEmail(Project__c newProj, Project__c oldProj, String oldStatus, String newStatus) {
        if (newStatus != oldStatus) {
            return (newStatus == STATUS_PENDING) ? isPendingRequestComplete(newProj) : true;
        }

        if (newStatus != STATUS_PENDING) {
            return false;
        }

        Boolean pendingDataChanged =
            newProj.Pending_Additional_Amount__c != oldProj.Pending_Additional_Amount__c ||
            newProj.Pending_Additional_Reason__c != oldProj.Pending_Additional_Reason__c;

        return pendingDataChanged && isPendingRequestComplete(newProj);
    }

    private static Boolean isPendingRequestComplete(Project__c p) {
        return p.Pending_Additional_Amount__c != null && p.Pending_Additional_Amount__c > 0
            && String.isNotBlank(p.Pending_Additional_Reason__c);
    }

    private static void dispatchEmail(Project__c newProj, Project__c oldProj, String newStatus) {
        if (newStatus == STATUS_PENDING) {
            // The request was just submitted (or resubmitted) - the amount/reason/attachments
            // being requested now are the current values on the record. Backfill history/
            // attachments first for sources (e.g. the mobile app's raw REST client) that set
            // the status field directly without going through submitRequest().
            String contentDocumentIdsCsv = ProjectAdditionalBudgetController.backfillPendingRequestIfNeeded(newProj.Id, newProj, oldProj);
            ProjectAdditionalBudgetController.sendManagerApprovalRequest(
                newProj.Id,
                newProj.Pending_Additional_Amount__c,
                newProj.Pending_Additional_Reason__c,
                contentDocumentIdsCsv
            );
        } else if (newStatus == STATUS_APPROVED) {
            // approveRequest clears the pending fields in this same update, so what the request
            // actually was only survives on the pre-update (old) record.
            ProjectAdditionalBudgetController.sendApprovedNotifications(
                newProj.Id,
                oldProj.Pending_Additional_Amount__c,
                oldProj.Pending_Additional_Reason__c,
                oldProj.Additional_Budget_ContentDocumentIds__c
            );
        } else if (newStatus == STATUS_REJECTED) {
            ProjectAdditionalBudgetController.sendRejectedNotifications(
                newProj.Id,
                oldProj.Pending_Additional_Amount__c,
                oldProj.Pending_Additional_Reason__c,
                newProj.Additional_Budget_Rejection_Reason__c,
                oldProj.Additional_Budget_ContentDocumentIds__c
            );
        }
    }
}