public with sharing class RefundSettlementService {

    public static void processRefunds(List<Booking__c> newBookings, Map<Id, Booking__c> oldMap) {
        Set<Id> checkedOutBookingIds = new Set<Id>();

        for (Booking__c b : newBookings) {
            Boolean isCheckedOut = (b.Status__c == 'Checked Out');
            Boolean wasCheckedOut = (oldMap != null && oldMap.containsKey(b.Id) && oldMap.get(b.Id).Status__c == 'Checked Out');

            if (isCheckedOut && !wasCheckedOut) {
                checkedOutBookingIds.add(b.Id);
            }
        }

        if (!checkedOutBookingIds.isEmpty() && !System.isQueueable() && !System.isFuture()) {
            System.enqueueJob(new RefundSettlementQueueable(checkedOutBookingIds));
        }
    }
}