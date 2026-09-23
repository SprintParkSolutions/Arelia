public with sharing class AreliaCaseNotificationHandler {

    public static void handleAfterUpdate(
        List<Case> newCases,
        Map<Id, Case> oldCaseMap
    ) {
        System.debug('CASE NOTIFICATION TRIGGER STARTED');

        if (newCases == null || newCases.isEmpty()) {
            return;
        }

        Set<Id> caseIds = new Set<Id>();

        for (Case caseRec : newCases) {
            if (caseRec.Id != null) {
                caseIds.add(caseRec.Id);
            }
        }

        if (caseIds.isEmpty()) {
            return;
        }

        List<Case> caseRecords = [
            SELECT Id,
                   Subject,
                   Status,
                   Priority,
                   ContactId,
                   Project__c,
                   Project__r.Name
            FROM Case
            WHERE Id IN :caseIds
        ];

        for (Case newCase : caseRecords) {
            Case oldCase = oldCaseMap.get(newCase.Id);

            if (oldCase == null) {
                continue;
            }

            if (newCase.ContactId == null) {
                System.debug(
                    'Case has no ContactId. Push skipped. Case Id: ' +
                    newCase.Id
                );
                continue;
            }

            String title;
            String messageBody;

            String caseSubject = String.isBlank(newCase.Subject)
                ? 'your support request'
                : newCase.Subject;

            String projectName = 'your project';

            if (
                newCase.Project__r != null &&
                !String.isBlank(newCase.Project__r.Name)
            ) {
                projectName = newCase.Project__r.Name;
            }

            if (oldCase.Status != newCase.Status) {
                title = 'Support Request Status Updated';

                messageBody =
                    'Your support request "' +
                    caseSubject +
                    '" for project "' +
                    projectName +
                    '" status changed to "' +
                    newCase.Status +
                    '".';

            } else if (oldCase.Priority != newCase.Priority) {
                title = 'Support Request Priority Updated';

                messageBody =
                    'Your support request "' +
                    caseSubject +
                    '" for project "' +
                    projectName +
                    '" priority changed to "' +
                    newCase.Priority +
                    '".';

            } else {
                System.debug(
                    'No watched Case field changed. Push skipped. Case Id: ' +
                    newCase.Id
                );
                continue;
            }

            AreliaPushNotificationService.sendToContactAsync(
                newCase.ContactId,
                title,
                messageBody,
                'case_update',
                String.valueOf(newCase.Id)
            );

            System.debug(
                'Case push queued. Case=' + newCase.Id +
                ', Contact=' + newCase.ContactId +
                ', Project=' + projectName +
                ', Status=' + newCase.Status +
                ', Priority=' + newCase.Priority
            );
        }

        System.debug('CASE NOTIFICATION TRIGGER FINISHED');
    }
}