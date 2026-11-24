public without sharing class ProspectProjectDetailsPushJob
    implements Queueable, Database.AllowsCallouts {

    private Id leadId;
    private String fcmToken;

    public ProspectProjectDetailsPushJob(
        Id leadId,
        String fcmToken
    ) {
        this.leadId = leadId;
        this.fcmToken = fcmToken;
    }

    public void execute(QueueableContext context) {

        System.debug('============================================');
        System.debug('PROJECT DETAILS PUSH JOB STARTED');
        System.debug('Lead Id: ' + leadId);
        System.debug('Job Id: ' + context.getJobId());
        System.debug('============================================');

        if (leadId == null) {
            throw new ProspectPushException(
                'Lead Id is null.'
            );
        }

        if (String.isBlank(fcmToken)) {
            throw new ProspectPushException(
                'FCM token is blank.'
            );
        }

        List<Lead> leads = [
            SELECT
                Id,
                Project_Request_Submitted__c
            FROM Lead
            WHERE Id = :leadId
            LIMIT 1
        ];

        if (leads.isEmpty()) {
            throw new ProspectPushException(
                'Lead not found: ' + leadId
            );
        }

        Lead prospect = leads[0];

        if (prospect.Project_Request_Submitted__c == true) {

            System.debug(
                'PROJECT DETAILS PUSH SKIPPED: ' +
                'Project details already submitted.'
            );

            return;
        }

        String title =
            'Complete Your Project Details';

        String body =
            'Please submit your project details to continue ' +
            'with the next steps of your Arelia project.';

        Map<String, String> dataPayload =
            new Map<String, String>{
                'recipientType' =>
                    'prospect',

                'leadId' =>
                    String.valueOf(leadId),

                'notificationType' =>
                    'PROJECT_DETAILS_REQUIRED',

                'actionType' =>
                    'OPEN_PROJECT_DETAILS',

                'route' =>
                    'prospect_project_details',

                'title' =>
                    title,

                'body' =>
                    body
            };

        FirebasePushService.sendPushToToken(
            fcmToken,
            title,
            body,
            dataPayload
        );

        System.debug('============================================');
        System.debug('PROJECT DETAILS PUSH SUCCESS');
        System.debug('Lead Id: ' + leadId);
        System.debug('============================================');
    }

    public class ProspectPushException
        extends Exception {
    }
}