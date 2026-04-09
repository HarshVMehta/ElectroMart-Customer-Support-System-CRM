public class CaseService {

    private static final String DEFAULT_QUEUE_NAME = 'Technical Support Queue';
    private static final String ESCALATION_QUEUE_NAME = 'Senior Escalation Queue';

    private static final Map<String, String> PRODUCT_QUEUE_BY_PRODUCT = new Map<String, String>{
        'Mobile' => 'Mobile Support Queue',
        'Laptop' => 'Laptop Support Queue',
        'Warranty' => 'Warranty Support Queue',
        'Television' => 'Television Support Queue',
        'Home Appliance' => 'Home Appliance Support Queue'
    };

    public static void assignQueue(List<Case> caseList) {

        if (caseList == null || caseList.isEmpty()) {
            return;
        }

        Map<String, Id> queueMap = new Map<String, Id>();

        for (Group g : [select Id, Name from Group where Type = 'Queue']) {
            queueMap.put(g.Name, g.Id);
        }

        Id defaultQueueId = queueMap.get(DEFAULT_QUEUE_NAME);
        Id escalationQueueId = queueMap.get(ESCALATION_QUEUE_NAME);

        for (Case c : caseList) {

            Id resolvedOwnerId;

            if (String.isNotBlank(c.Product__c) && PRODUCT_QUEUE_BY_PRODUCT.containsKey(c.Product__c)) {
                resolvedOwnerId = queueMap.get(PRODUCT_QUEUE_BY_PRODUCT.get(c.Product__c));
            }

            if (c.Priority == 'High' && escalationQueueId != null) {
                resolvedOwnerId = escalationQueueId;
            }

            if (resolvedOwnerId == null) {
                resolvedOwnerId = defaultQueueId;
            }

            if (resolvedOwnerId == null) {
                resolvedOwnerId = c.OwnerId;
            }

            // Final safety net so trigger never leaves owner blank.
            if (resolvedOwnerId == null) {
                resolvedOwnerId = UserInfo.getUserId();
            }

            c.OwnerId = resolvedOwnerId;
        }
    }
}