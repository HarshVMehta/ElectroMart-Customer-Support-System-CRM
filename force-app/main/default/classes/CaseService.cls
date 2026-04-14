public class CaseService {

    private static final String MOBILE_QUEUE = 'Mobile Support Queue';
    private static final String LAPTOP_QUEUE = 'Laptop Support Queue';
    private static final String WARRANTY_QUEUE = 'Warranty Support Queue';
    private static final String TELEVISION_QUEUE = 'Television Support Queue';
    private static final String HOME_APPLIANCE_QUEUE = 'Home Appliance Support Queue';
    private static final String TECHNICAL_QUEUE = 'Technical Support Queue';
    private static final String ESCALATION_QUEUE = 'Senior Escalation Queue';

    public static void assignQueue(List<Case> caseList) {

        if (caseList == null || caseList.isEmpty()) {
            return;
        }

        Map<String, Id> queueMap = new Map<String, Id>();

        for (Group g : [select Id, Name from Group where Type = 'Queue']) {
            queueMap.put(g.Name, g.Id);
        }

        for (Case c : caseList) {

            String queueName = resolveQueueName(c);

            if (String.isNotBlank(queueName)) {
                if (queueMap.containsKey(queueName)) {
                    c.OwnerId = queueMap.get(queueName);
                }
                else if (queueMap.containsKey(TECHNICAL_QUEUE)) {
                    c.OwnerId = queueMap.get(TECHNICAL_QUEUE);
                }
            }
            else if (queueMap.containsKey(TECHNICAL_QUEUE)) {
                c.OwnerId = queueMap.get(TECHNICAL_QUEUE);
            }

            if (c.Priority == 'High') {
                c.OwnerId = queueMap.get(ESCALATION_QUEUE);
            }

            if (c.OwnerId == null) {
                c.OwnerId = UserInfo.getUserId();
            }
        }
    }

    private static String resolveQueueName(Case c) {
        if (c == null) {
            return TECHNICAL_QUEUE;
        }

        // First preference: explicit product selection from web form.
        String queueFromProduct = resolveQueueByProduct(c.Product__c);
        if (String.isNotBlank(queueFromProduct)) {
            return queueFromProduct;
        }

        // Second preference: infer from subject for Email-to-Case records.
        String queueFromSubject = resolveQueueByText(c.Subject);
        if (String.isNotBlank(queueFromSubject)) {
            return queueFromSubject;
        }

        // Third preference: check description only when subject has no keyword match.
        String queueFromDescription = resolveQueueByText(c.Description);
        if (String.isNotBlank(queueFromDescription)) {
            return queueFromDescription;
        }

        return TECHNICAL_QUEUE;
    }

    private static String resolveQueueByProduct(String productValue) {
        if (String.isBlank(productValue)) {
            return null;
        }

        // Normalize separators so free-text integrations can still map correctly.
        String normalized = productValue.trim().toLowerCase().replace('_', ' ').replace('-', ' ');

        if (containsAny(normalized, new List<String>{ 'mobile', 'phone' })) {
            return MOBILE_QUEUE;
        }

        if (containsAny(normalized, new List<String>{ 'laptop', 'notebook' })) {
            return LAPTOP_QUEUE;
        }

        if (containsAny(normalized, new List<String>{ 'warranty', 'warrenty' })) {
            return WARRANTY_QUEUE;
        }

        if (containsAny(normalized, new List<String>{ 'television', 'tv' })) {
            return TELEVISION_QUEUE;
        }

        if (containsAny(normalized, new List<String>{
            'home appliance',
            'home appliances',
            'appliance',
            'appliances',
            'applicance',
            'applicances',
            'applicane',
            'applicanes'
        })) {
            return HOME_APPLIANCE_QUEUE;
        }

        return null;
    }

    private static String resolveQueueByText(String sourceText) {
        if (String.isBlank(sourceText)) {
            return null;
        }

        String text = sourceText.toLowerCase();

        if (containsAny(text, new List<String>{ 'warranty', 'claim', 'replacement', 'refund', 'guarantee' })) {
            return WARRANTY_QUEUE;
        }

        if (containsAny(text, new List<String>{ 'television', 'smart tv', 'tv ', 'hdmi', 'remote control' })) {
            return TELEVISION_QUEUE;
        }

        if (containsAny(text, new List<String>{ 'mobile', 'phone', 'android', 'ios', 'sim' })) {
            return MOBILE_QUEUE;
        }

        if (containsAny(text, new List<String>{ 'laptop', 'notebook', 'touchpad', 'keyboard', 'trackpad' })) {
            return LAPTOP_QUEUE;
        }

        if (containsAny(text, new List<String>{
            'home appliance',
            'refrigerator',
            'fridge',
            'washing machine',
            'microwave',
            'dishwasher',
            'air conditioner',
            'vacuum cleaner'
        })) {
            return HOME_APPLIANCE_QUEUE;
        }

        return null;
    }

    private static Boolean containsAny(String text, List<String> keywords) {
        if (String.isBlank(text) || keywords == null || keywords.isEmpty()) {
            return false;
        }

        for (String keyword : keywords) {
            if (String.isNotBlank(keyword) && text.contains(keyword)) {
                return true;
            }
        }

        return false;
    }

    public static void sendEmailToCaseAcknowledgements(List<Case> caseList) {
        // Placeholder kept to satisfy trigger-handler dependency.
        // Email acknowledgement behavior can be expanded here when required.
        if (caseList == null || caseList.isEmpty()) {
            return;
        }
    }
}