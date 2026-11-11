trigger AreliaPlatformEventTrigger on Arelia_Platform_Event__e (after insert) {

    // Architecture Design records
    Map<Id, Date> architectureDatesById = new Map<Id, Date>();

    // Proforma Invoice records
    Map<Id, Date> proformaDatesById = new Map<Id, Date>();

    // Opportunity Budget Review records
    Map<Id, Date> budgetReviewDatesById = new Map<Id, Date>();
        
    // Opportunity Payment tems records
    Map<Id, Date> paymenTermsDatesById = new Map<Id, Date>();    

    // =====================================================
    // 1. READ AND VALIDATE PLATFORM EVENT RECORDS
    // =====================================================

    for (Arelia_Platform_Event__e eventRecord : Trigger.new) {

        // Architecture Design
        if ( !String.isBlank( eventRecord.Architect_Approved_Record_ID__c ) && eventRecord.Architect_Approved_Date__c != null )
        {
            try {
                Id recordId = Id.valueOf( eventRecord.Architect_Approved_Record_ID__c );

                if ( recordId.getSObjectType() == Architecture_Design__c.SObjectType )
                {
                    architectureDatesById.put( recordId, eventRecord.Architect_Approved_Date__c );
                }
            } catch (Exception ex) {
                System.debug( LoggingLevel.ERROR, 'Invalid Architecture Design ID: ' + ex.getMessage() );
            }
        }

        // Proforma Invoice
        if (!String.isBlank( eventRecord.Proforma_Invoice_Approved_Record_ID__c ) && eventRecord.Proforma_Invoice_Approved_date__c != null ) {
            try {
                Id recordId = Id.valueOf( eventRecord.Proforma_Invoice_Approved_Record_ID__c );

                if (recordId.getSObjectType() == Proforma_Invoice__c.SObjectType )
                {
                    proformaDatesById.put( recordId, eventRecord.Proforma_Invoice_Approved_date__c );
                }
            } catch (Exception ex) {
                System.debug(LoggingLevel.ERROR, 'Invalid Proforma Invoice ID: ' + ex.getMessage() );
            }
        }

        // Opportunity Budget Review
        if (!String.isBlank(eventRecord.Budget_Review_Approved_Record_ID__c) && eventRecord.Budget_Review_Approved_Date__c != null)
        {
            try {
                Id recordId = Id.valueOf(eventRecord.Budget_Review_Approved_Record_ID__c);

                if (recordId.getSObjectType() == Opportunity.SObjectType )
                { 
                    budgetReviewDatesById.put( recordId, eventRecord.Budget_Review_Approved_Date__c);
                }
            } catch (Exception ex) {
                System.debug( LoggingLevel.ERROR, 'Invalid Opportunity ID: ' + ex.getMessage() );
            }
        }

        // Opportunity payment terms
        if ( !String.isBlank( eventRecord.Payment_Terms_Approved_Record_ID__c ) && eventRecord.Payment_Terms_Approved_Date__c != null )
        {
            try {
                Id recordId = Id.valueOf( eventRecord.Payment_Terms_Approved_Record_ID__c );

                if ( recordId.getSObjectType() == Opportunity.SObjectType ) {
                    paymenTermsDatesById.put(recordId, eventRecord.Payment_Terms_Approved_Date__c );
                }
            } catch (Exception ex) {
                System.debug( LoggingLevel.ERROR, 'Invalid Opportunity ID: ' + ex.getMessage() );
            }
        }
        
    }

    // =====================================================
    // 2. UPDATE ARCHITECTURE DESIGN RECORDS
    // =====================================================

    if (!architectureDatesById.isEmpty()) {

        List<Architecture_Design__c> designsToUpdate = new List<Architecture_Design__c>();

        for (Architecture_Design__c design : [ SELECT Id, Architect_Approved_Date__c FROM Architecture_Design__c WHERE Id IN :architectureDatesById.keySet() ])
        {
            Date approvedDate = architectureDatesById.get(design.Id);

            if (design.Architect_Approved_Date__c != approvedDate)
            {
                design.Architect_Approved_Date__c = approvedDate;
                designsToUpdate.add(design);
            }
        }

        if (!designsToUpdate.isEmpty()) {
            update designsToUpdate;
        }
    }

    // =====================================================
    // 3. UPDATE PROFORMA INVOICE RECORDS
    // =====================================================

    if (!proformaDatesById.isEmpty()) {

        List<Proforma_Invoice__c> invoicesToUpdate = new List<Proforma_Invoice__c>();

        for (Proforma_Invoice__c invoice : [SELECT Id, Proforma_Invoice_Approved_date__c FROM Proforma_Invoice__c WHERE Id IN :proformaDatesById.keySet()])
        {
            Date approvedDate = proformaDatesById.get(invoice.Id);

            if ( invoice.Proforma_Invoice_Approved_date__c != approvedDate ) {
                invoice.Proforma_Invoice_Approved_date__c = approvedDate;
                invoicesToUpdate.add(invoice);
            }
        }

        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
    }

    // =====================================================
    // 4. UPDATE OPPORTUNITY BUDGET REVIEW RECORDS
    // =====================================================

    if (!budgetReviewDatesById.isEmpty()) {

        List<Opportunity> oppBudgetReviewToUpdate = new List<Opportunity>();

        for (Opportunity opportunityRecord : [ SELECT Id, Budget_Review_Approved_Date__c FROM Opportunity WHERE Id IN :budgetReviewDatesById.keySet()])
        {
            Date approvedDate = budgetReviewDatesById.get(opportunityRecord.Id);

            if ( opportunityRecord.Budget_Review_Approved_Date__c != approvedDate )
            {
                opportunityRecord.Budget_Review_Approved_Date__c = approvedDate;
                oppBudgetReviewToUpdate.add(opportunityRecord);
            }
        }

        if (!oppBudgetReviewToUpdate.isEmpty()) {
            update oppBudgetReviewToUpdate;
        }
    }
    
    
    // =====================================================
    // 5. UPDATE OPPORTUNITY PAYMENT TERMS RECORDS
    // =====================================================

    if (!paymenTermsDatesById.isEmpty()) {

        List<Opportunity> oppPaymentTermsToUpdate = new List<Opportunity>();

        for (Opportunity opportunityRecord : [ SELECT Id,Payment_Terms_Approved_Date__c FROM Opportunity WHERE Id IN :paymenTermsDatesById.keySet()])
        {
            Date approvedDate = paymenTermsDatesById.get(opportunityRecord.Id);

            if ( opportunityRecord.Payment_Terms_Approved_Date__c != approvedDate )
            {
                opportunityRecord.Payment_Terms_Approved_Date__c = approvedDate;
                oppPaymentTermsToUpdate.add(opportunityRecord);
            }
        }

        if (!oppPaymentTermsToUpdate.isEmpty()) {
            update oppPaymentTermsToUpdate;
        }
    }


    System.debug( LoggingLevel.INFO, 'Platform Event processed. Architecture Designs=' +  architectureDatesById.size() +
        ', Proforma Invoices=' + proformaDatesById.size() + ', Opportunities=' + budgetReviewDatesById.size() );
}