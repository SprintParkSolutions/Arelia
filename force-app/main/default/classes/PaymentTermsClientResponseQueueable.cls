public without sharing class PaymentTermsClientResponseQueueable
    implements Queueable {

    private Id opportunityId;
    private String statusValue;
    private String comments;


    public PaymentTermsClientResponseQueueable(
        Id opportunityId,
        String statusValue,
        String comments
    ) {
        this.opportunityId =
            opportunityId;

        this.statusValue =
            statusValue;

        this.comments =
            comments;
    }


    public void execute(
        QueueableContext context
    ) {

        if (
            opportunityId == null ||
            String.isBlank(statusValue)
        ) {
            return;
        }


        List<Opportunity> opportunities =
            Database.query(
                'SELECT ' +
                    'Id, ' +
                    'Payment_Terms_Status__c, ' +
                    'Payment_Term_Client_Remarks__c ' +
                'FROM Opportunity ' +
                'WHERE Id = :opportunityId ' +
                'LIMIT 1',
                AccessLevel.SYSTEM_MODE
            );

        if (opportunities.isEmpty()) {
            return;
        }


        Opportunity opportunity =
            opportunities[0];

        opportunity.Payment_Terms_Status__c =
            statusValue;


        if (!String.isBlank(comments)) {

            opportunity
                .Payment_Term_Client_Remarks__c =
                comments.trim();

        } else if (
            statusValue ==
            'Client Approved'
        ) {

            opportunity
                .Payment_Term_Client_Remarks__c =
                null;
        }


        Database.update(
            opportunity,
            AccessLevel.SYSTEM_MODE
        );
    }
}