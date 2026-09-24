public with sharing class RefundSettlementQueueable implements Queueable {
    private Set<Id> bookingIds;

    public RefundSettlementQueueable(Set<Id> bookingIds) {
        this.bookingIds = bookingIds;
    }

    public void execute(QueueableContext context) {
        if (bookingIds == null || bookingIds.isEmpty()) return;

        List<Booking__c> bookings = [SELECT Id, Guest__c, Check_Out_Due__c, Actual_Check_Out__c, Deposit__c, Room__r.Nightly_Rate__c FROM Booking__c WHERE Id IN :bookingIds];

        Set<Id> guestIds = new Set<Id>();
        for (Booking__c b : bookings) { if (b.Guest__c != null) guestIds.add(b.Guest__c);}

        //(c)Loyalty adjustment: a guest who has already checked out of 3 or more bookings in the past, not counting the check-outs being settled right now, pays only half the late fee. 
        Map<Id, Integer> guestPastCheckoutCounts = new Map<Id, Integer>();
        if (!guestIds.isEmpty()) {
            for (AggregateResult ar : [SELECT Guest__c gId, COUNT(Id) total FROM Booking__c WHERE Guest__c IN :guestIds   AND Status__c = 'Checked Out' AND Id NOT IN :bookingIds GROUP BY Guest__c]) {
                guestPastCheckoutCounts.put((Id)ar.get('gId'), (Integer)ar.get('total'));
            }
        }

        Decimal totalRefunded = 0;
        Integer processedCount = 0;
        List<Booking__c> bookingsToUpdate = new List<Booking__c>();

        for (Booking__c b : bookings) {
            try {
                Date actualOut = b.Actual_Check_Out__c != null ? b.Actual_Check_Out__c : Date.today();
                Date dueOut = b.Check_Out_Due__c;
                
                Integer daysOver = 0;
                if (actualOut > dueOut) {daysOver = dueOut.daysBetween(actualOut);}

                Decimal nightlyRate = (b.Room__r != null && b.Room__r.Nightly_Rate__c != null) ? b.Room__r.Nightly_Rate__c : 0;
                Decimal baseLateFee = daysOver * (nightlyRate * 0.30);
                Integer pastCheckouts = guestPastCheckoutCounts.containsKey(b.Guest__c) ? guestPastCheckoutCounts.get(b.Guest__c) : 0;
                Decimal finalLateFee = (pastCheckouts >= 3) ? (baseLateFee * 0.50) : baseLateFee;
                Decimal deposit = b.Deposit__c != null ? b.Deposit__c : 0;
                Decimal refundAmount = Math.max(0, deposit - finalLateFee);

                b.Late_Fee__c = finalLateFee;
                b.Refund_Amount__c = refundAmount;
                b.Refund_Status__c = 'Processed';
                
                bookingsToUpdate.add(b);
            } catch (Exception e) {
                b.Refund_Status__c = 'Failed';
                bookingsToUpdate.add(b);
            }
        }

        if (!bookingsToUpdate.isEmpty()) {
            List<Database.SaveResult> results = Database.update(bookingsToUpdate, false);
            List<Error_Log__c> errorLogs = new List<Error_Log__c>();

            for (Integer i = 0; i < results.size(); i++) {
                Database.SaveResult sr = results[i];
                Booking__c b = bookingsToUpdate[i];

                if (sr.isSuccess()) {
                    if (b.Refund_Status__c == 'Processed') {
                        processedCount++;
                        totalRefunded += (b.Refund_Amount__c != null ? b.Refund_Amount__c : 0);
                    }
                } else {
                    String errorMsg = '';
                    for (Database.Error err : sr.getErrors()) {
                        errorMsg += err.getMessage() + ' ';
                    }
                    errorLogs.add(new Error_Log__c(
                        Source__c = 'RefundSettlementQueueable',
                        Message__c = errorMsg,
                        Record_Reference__c = b.Id
                    ));
                }
            }

            if (!errorLogs.isEmpty()) { insert errorLogs;}
        }

        if (processedCount > 0) {
            insert new Process_Summary__c(
                Process__c = 'Refund Run',
                Records_Processed__c = processedCount,
                Total_Amount__c = totalRefunded
            );
        }
    }
}