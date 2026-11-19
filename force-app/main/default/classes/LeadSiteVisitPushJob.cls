public without sharing class LeadSiteVisitPushJob
    implements Queueable, Database.AllowsCallouts {

    private Set<Id> leadIds;

    public LeadSiteVisitPushJob(Set<Id> leadIds) {
        this.leadIds = new Set<Id>(leadIds);
    }

    public void execute(QueueableContext context) {

        if (leadIds.isEmpty()) return;

        Map<Id, Lead> leads = new Map<Id, Lead>([
            SELECT Id, Name,
                   Appointment_Date__c,
                   Appointment_Time_Slots__c,
                   Appointment_Confirmation_Type__c,
                   Appointment_Status__c,
                   Site_Location__c,
                   Supervisor_User__c,
                   Supervisor_User__r.Name
            FROM Lead
            WHERE Id IN :leadIds
        ]);

        List<Prospect_Device_Token__c> devices = [
            SELECT Id, Prospect_Lead__c,
                   FCM_Token__c, Last_Seen__c
            FROM Prospect_Device_Token__c
            WHERE Prospect_Lead__c IN :leadIds
              AND Active__c = true
            ORDER BY Last_Seen__c DESC NULLS LAST
        ];

        // Select the newest active token per Lead.
        Map<Id, String> tokens = new Map<Id, String>();

        for (Prospect_Device_Token__c device : devices) {
            if (device.Prospect_Lead__c != null &&
                !String.isBlank(device.FCM_Token__c) &&
                !tokens.containsKey(device.Prospect_Lead__c)) {

                tokens.put(
                    device.Prospect_Lead__c,
                    device.FCM_Token__c
                );
            }
        }

        for (Lead prospect : leads.values()) {

            String token = tokens.get(prospect.Id);

            if (String.isBlank(token) ||
                prospect.Appointment_Date__c == null ||
                String.isBlank(
                    prospect.Appointment_Time_Slots__c
                )) {
                continue;
            }

            String title = 'Site Visit Scheduled';

            String body =
                'Your site visit has been scheduled for ' +
                String.valueOf(prospect.Appointment_Date__c) +
                ' (' +
                prospect.Appointment_Time_Slots__c +
                '). Tap to review the details and confirm your availability.';

            String supervisorName = '';

            if (prospect.Supervisor_User__r != null) {
                supervisorName =
                    prospect.Supervisor_User__r.Name;
            }

            String eventId =
                'SITE_VISIT_SCHEDULED:' +
                String.valueOf(prospect.Id) + ':' +
                String.valueOf(prospect.Appointment_Date__c) +
                ':' + prospect.Appointment_Time_Slots__c;

            Map<String, String> payload =
                new Map<String, String>{
                    'id' => eventId,
                    'title' => title,
                    'body' => body,
                    'time' => Datetime.now().formatGMT(
                        'yyyy-MM-dd\'T\'HH:mm:ss.SSS\'Z\''
                    ),
                    'source' => 'Lead',
                    'recordId' => String.valueOf(prospect.Id),
                    'recipientType' => 'prospect',
                    'leadId' => String.valueOf(prospect.Id),
                    'notificationType' => 'SITE_VISIT_SCHEDULED',
                    'actionType' => 'OPEN_SITE_VISIT_APPROVAL',
                    'route' => 'prospect_site_visit_approval',
                    'appointmentDate' =>
                        String.valueOf(prospect.Appointment_Date__c),
                    'appointmentTimeSlot' =>
                        prospect.Appointment_Time_Slots__c,
                    'appointmentType' =>
                        prospect.Appointment_Confirmation_Type__c == null
                            ? ''
                            : prospect.Appointment_Confirmation_Type__c,
                    'appointmentStatus' =>
                        prospect.Appointment_Status__c == null
                            ? ''
                            : prospect.Appointment_Status__c,
                    'siteLocation' =>
                        String.isBlank(prospect.Site_Location__c)
                            ? ''
                            : prospect.Site_Location__c,
                    'supervisorName' => supervisorName
                };

            FirebasePushService.sendPushToToken(
                token,
                title,
                body,
                payload
            );
        }
    }
}