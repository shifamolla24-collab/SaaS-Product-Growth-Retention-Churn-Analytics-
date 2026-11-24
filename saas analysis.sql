CREATE DATABASE saas_product_analytics;
USE saas_product_analytics;
SHOW TABLES;
SELECT * FROM eligible_users;
SELECT * FROM `users_clean - copy` ;
SELECT * FROM subscriptions_clean;
SELECT * FROM payments_clean;
SELECT * FROM events_clean;
SELECT * FROM monthly_subscription_metrics;
SELECT * FROM monthly_signups;
SELECT * FROM marketing_spend_clean;
SELECT * FROM customer_analysis;
SELECT * FROM cleaned_users ;


-- Section 1 — Funnel and acquisition analytics
-- Q1. What is the conversion rate from signup to activation and paid subscription, overall and by acquisition channel?
WITH user_funnel AS (
    SELECT
        u.user_id,
        u.acquisition_channel,
        MAX(
            CASE
                WHEN LOWER(COALESCE(e.event_name, '')) LIKE '%project%'
                THEN 1 ELSE 0
            END
        ) AS activated,
        MAX(
            CASE
                WHEN LOWER(COALESCE(s.status, '')) IN
                     ('active', 'paid', 'trialing')
                     AND LOWER(COALESCE(s.status, '')) <> 'trialing'
                THEN 1 ELSE 0
            END
        ) AS paid
    FROM eligible_users u
    LEFT JOIN events_clean e
        ON u.user_id = e.user_id
    LEFT JOIN subscriptions_clean s
        ON u.user_id = s.user_id
    WHERE LOWER(COALESCE(u.is_internal_test, 'false'))
          NOT IN ('1', 'true', 'yes')
    GROUP BY u.user_id, u.acquisition_channel
)
SELECT
    COALESCE(acquisition_channel, 'Unknown') AS acquisition_channel,
    COUNT(*) AS signups,
    SUM(activated) AS activated_users,
    ROUND(100.0 * SUM(activated) / NULLIF(COUNT(*), 0), 2)
        AS activation_rate_pct,
    SUM(paid) AS paid_users,
    ROUND(100.0 * SUM(paid) / NULLIF(COUNT(*), 0), 2)
        AS signup_to_paid_pct
FROM user_funnel
GROUP BY acquisition_channel
ORDER BY signup_to_paid_pct DESC;

-- Q2. What is the median number of days between signup and the first subscription?
WITH first_subscription AS (
    SELECT
        user_id,
        MIN(STR_TO_DATE(start_date, '%Y-%m-%d')) AS first_paid_date
    FROM subscriptions_clean
    WHERE STR_TO_DATE(start_date, '%Y-%m-%d') IS NOT NULL
    GROUP BY user_id
),
durations AS (
    SELECT
        u.user_id,
        DATEDIFF(
            s.first_paid_date,
            STR_TO_DATE(u.signup_date, '%Y-%m-%d')
        ) AS days_to_paid
    FROM eligible_users u
    JOIN first_subscription s ON u.user_id = s.user_id
    WHERE STR_TO_DATE(u.signup_date, '%Y-%m-%d') IS NOT NULL
      AND s.first_paid_date >=
          STR_TO_DATE(u.signup_date, '%Y-%m-%d')
),
ranked AS (
    SELECT
        days_to_paid,
        ROW_NUMBER() OVER (ORDER BY days_to_paid) AS rn,
        COUNT(*) OVER () AS total_rows
    FROM durations
)
SELECT
    AVG(days_to_paid) AS median_days_to_paid
FROM ranked
WHERE rn IN (
    FLOOR((total_rows + 1) / 2),
    FLOOR((total_rows + 2) / 2)
);

-- Q3. Which acquisition channel has the highest and lowest signup-to-subscription conversion rate?
WITH user_paid AS (
    SELECT
        u.user_id,
        u.acquisition_channel,
        MAX(
            CASE
                WHEN s.user_id IS NOT NULL THEN 1
                ELSE 0
            END
        ) AS converted
    FROM eligible_users u
    LEFT JOIN subscriptions_clean s
        ON u.user_id = s.user_id
    WHERE LOWER(COALESCE(u.is_internal_test, 'false'))
          NOT IN ('1', 'true', 'yes')
    GROUP BY u.user_id, u.acquisition_channel
),
channel_rates AS (
    SELECT
        acquisition_channel,
        COUNT(*) AS signups,
        SUM(converted) AS subscribed_users,
        ROUND(100.0 * SUM(converted) / NULLIF(COUNT(*), 0), 2)
            AS conversion_rate_pct
    FROM user_paid
    GROUP BY acquisition_channel
)
SELECT
    *,
    RANK() OVER (ORDER BY conversion_rate_pct DESC) AS highest_rank,
    RANK() OVER (ORDER BY conversion_rate_pct ASC) AS lowest_rank
FROM channel_rates
ORDER BY conversion_rate_pct DESC;

-- Q4. What percentage of users activate within seven days of signup?
WITH activation AS (
    SELECT
        u.user_id,
        STR_TO_DATE(u.signup_date, '%Y-%m-%d') AS signup_dt,
        MIN(STR_TO_DATE(e.event_time, '%Y-%m-%d %H:%i:%s'))
            AS first_project_event
    FROM eligible_users u
    LEFT JOIN events_clean e
        ON u.user_id = e.user_id
       AND LOWER(COALESCE(e.event_name, '')) LIKE '%project%'
    WHERE STR_TO_DATE(u.signup_date, '%Y-%m-%d') IS NOT NULL
      AND LOWER(COALESCE(u.is_internal_test, 'false'))
          NOT IN ('1', 'true', 'yes')
    GROUP BY u.user_id, u.signup_date
)
SELECT
    COUNT(*) AS total_users,
    SUM(
        CASE
            WHEN first_project_event >= signup_dt
             AND first_project_event < DATE_ADD(signup_dt, INTERVAL 7 DAY)
            THEN 1 ELSE 0
        END
    ) AS activated_within_7_days,
    ROUND(
        100.0 * SUM(
            CASE
                WHEN first_project_event >= signup_dt
                 AND first_project_event < DATE_ADD(signup_dt, INTERVAL 7 DAY)
                THEN 1 ELSE 0
            END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS activation_rate_pct
FROM activation;

-- Q5. Which device and company-size groups have the largest activation drop-off?
WITH user_device AS (
    SELECT
        u.user_id,
        u.company_size,
        COALESCE(e.device, 'Unknown') AS device,
        MAX(
            CASE
                WHEN LOWER(COALESCE(e.event_name, '')) LIKE '%project%'
                THEN 1 ELSE 0
            END
        ) AS activated
    FROM eligible_users u
    LEFT JOIN events_clean e
        ON u.user_id = e.user_id
    WHERE LOWER(COALESCE(u.is_internal_test, 'false'))
          NOT IN ('1', 'true', 'yes')
    GROUP BY u.user_id, u.company_size, COALESCE(e.device, 'Unknown')
)
SELECT
    device,
    company_size,
    COUNT(*) AS users,
    SUM(activated) AS activated_users,
    COUNT(*) - SUM(activated) AS not_activated,
    ROUND(
        100.0 * (COUNT(*) - SUM(activated)) / NULLIF(COUNT(*), 0),
        2
    ) AS dropoff_pct
FROM user_device
GROUP BY device, company_size
ORDER BY dropoff_pct DESC;

-- Section 2 — MRR and revenue growth
-- Q6. What are the monthly recurring revenue (MRR), annual recurring revenue (ARR), and paying customers?
SELECT
    snapshot_month,
    paying_customers,
    subscription_periods,
    CAST(observed_mrr AS DECIMAL(18,2)) AS mrr,
    ROUND(CAST(observed_mrr AS DECIMAL(18,2)) * 12, 2) AS arr
FROM monthly_subscription_metrics
ORDER BY snapshot_month;

-- Q7 
    
WITH subscription_values AS (
    SELECT
        subscription_id,
        user_id,
        STR_TO_DATE(NULLIF(TRIM(start_date), ''), '%Y-%m-%d') AS start_dt,
        STR_TO_DATE(NULLIF(TRIM(end_date), ''), '%Y-%m-%d') AS end_dt,
        CAST(NULLIF(TRIM(mrr), '') AS DECIMAL(18,2)) AS mrr_value
    FROM subscriptions_clean
),

movements AS (
    SELECT
        DATE_FORMAT(start_dt, '%Y-%m-01') AS movement_month,
        'Started MRR' AS movement_type,
        SUM(mrr_value) AS mrr_amount
    FROM subscription_values
    WHERE start_dt IS NOT NULL
    GROUP BY DATE_FORMAT(start_dt, '%Y-%m-01')

    UNION ALL

    SELECT
        DATE_FORMAT(end_dt, '%Y-%m-01') AS movement_month,
        'Ended MRR' AS movement_type,
        SUM(mrr_value) AS mrr_amount
    FROM subscription_values
    WHERE end_dt IS NOT NULL
    GROUP BY DATE_FORMAT(end_dt, '%Y-%m-01')
)

SELECT
    movement_month,
    movement_type,
    ROUND(mrr_amount, 2) AS mrr_amount
FROM movements
GROUP BY movement_month, movement_type, mrr_amount
ORDER BY movement_month, movement_type;

-- Q8. What is the month-over-month MRR growth and three-month rolling average?

WITH monthly AS (
    SELECT
        STR_TO_DATE(
            CONCAT(snapshot_month, '-01'),
            '%Y-%m-%d'
        ) AS month_date,
        CAST(observed_mrr AS DECIMAL(18,2)) AS mrr
    FROM monthly_subscription_metrics
),
growth AS (
    SELECT
        month_date,
        mrr,
        LAG(mrr) OVER (ORDER BY month_date) AS previous_mrr,
        AVG(mrr) OVER (
            ORDER BY month_date
            ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
        ) AS rolling_3_month_mrr
    FROM monthly
)
SELECT
    DATE_FORMAT(month_date, '%Y-%m') AS month,
    mrr,
    previous_mrr,
    ROUND(
        100.0 * (mrr - previous_mrr) / NULLIF(previous_mrr, 0),
        2
    ) AS mom_growth_pct,
    ROUND(rolling_3_month_mrr, 2) AS rolling_3_month_avg_mrr
FROM growth
ORDER BY month_date;

-- Q9. What is the MRR share by subscription plan and country?
WITH user_plan_mrr AS (
    SELECT
        user_id,
        plan,
        SUM(
            CAST(NULLIF(TRIM(mrr), '') AS DECIMAL(18,2))
        ) AS plan_mrr
    FROM subscriptions_clean
    WHERE LOWER(COALESCE(status, '')) = 'active'
    GROUP BY user_id, plan
),
plan_country AS (
    SELECT
        COALESCE(p.plan, 'Unknown') AS plan,
        COALESCE(u.country, 'Unknown') AS country,
        SUM(p.plan_mrr) AS mrr
    FROM user_plan_mrr p
    LEFT JOIN eligible_users u
        ON p.user_id = u.user_id
    GROUP BY p.plan, u.country
)
SELECT
    plan,
    country,
    ROUND(mrr, 2) AS mrr,
    ROUND(
        100.0 * mrr / NULLIF(SUM(mrr) OVER (), 0),
        2
    ) AS total_mrr_share_pct
FROM plan_country
ORDER BY mrr DESC;

-- Q10. What is average revenue per account (ARPA) by plan and billing cycle?
WITH customer_plan AS (
    SELECT
        user_id,
        plan,
        billing_cycle,
        SUM(
            CAST(NULLIF(TRIM(mrr), '') AS DECIMAL(18,2))
        ) AS customer_mrr
    FROM subscriptions_clean
    WHERE LOWER(COALESCE(status, '')) = 'active'
    GROUP BY user_id, plan, billing_cycle
)
SELECT
    plan,
    billing_cycle,
    COUNT(DISTINCT user_id) AS paying_customers,
    ROUND(SUM(customer_mrr), 2) AS total_mrr,
    ROUND(
        SUM(customer_mrr) / NULLIF(COUNT(DISTINCT user_id), 0),
        2
    ) AS arpa
FROM customer_plan
GROUP BY plan, billing_cycle
ORDER BY arpa DESC;

-- Q11. What are the monthly net revenue retention (NRR) and gross revenue retention (GRR)?


WITH customer_months AS (
    SELECT
        user_id,
        STR_TO_DATE(
            NULLIF(TRIM(start_date), ''),
            '%Y-%m-%d'
        ) AS start_dt,
        STR_TO_DATE(
            NULLIF(TRIM(end_date), ''),
            '%Y-%m-%d'
        ) AS end_dt,
        CAST(
            NULLIF(TRIM(mrr), '')
            AS DECIMAL(18,2)
        ) AS mrr_value
    FROM subscriptions_clean
),

monthly_mrr AS (
    SELECT
        DATE_FORMAT(start_dt, '%Y-%m-01') AS month,
        SUM(mrr_value) AS started_mrr
    FROM customer_months
    WHERE start_dt IS NOT NULL
    GROUP BY DATE_FORMAT(start_dt, '%Y-%m-01')
)

SELECT
    month,
    ROUND(started_mrr, 2) AS started_mrr
FROM monthly_mrr
ORDER BY month;

-- Section 3 — Cohort and retention analytics
-- Q12. What are Month-1, Month-3, Month-6, and Month-12 retention rates by signup cohort?

WITH user_cohorts AS (
    SELECT
        user_id,
        STR_TO_DATE(signup_date, '%Y-%m-%d') AS signup_dt,
        STR_TO_DATE(
            DATE_FORMAT(
                STR_TO_DATE(signup_date, '%Y-%m-%d'),
                '%Y-%m-01'
            ),
            '%Y-%m-%d'
        ) AS cohort_month
    FROM eligible_users
    WHERE STR_TO_DATE(signup_date, '%Y-%m-%d') IS NOT NULL
      AND LOWER(COALESCE(is_internal_test, 'false'))
          NOT IN ('1', 'true', 'yes')
),
retention AS (
    SELECT
        c.user_id,
        c.cohort_month,
        MAX(CASE WHEN TIMESTAMPDIFF(
            MONTH, c.cohort_month,
            STR_TO_DATE(s.start_date, '%Y-%m-%d')
        ) >= 1
        AND TIMESTAMPDIFF(
            MONTH, c.cohort_month,
            STR_TO_DATE(s.start_date, '%Y-%m-%d')
        ) <= 1
        AND (
            NULLIF(TRIM(s.end_date), '') IS NULL
            OR STR_TO_DATE(s.end_date, '%Y-%m-%d') >=
               DATE_ADD(c.cohort_month, INTERVAL 2 MONTH)
        ) THEN 1 ELSE 0 END) AS m1_retained,
        MAX(CASE WHEN STR_TO_DATE(s.start_date, '%Y-%m-%d')
            < DATE_ADD(c.cohort_month, INTERVAL 4 MONTH)
        AND (
            NULLIF(TRIM(s.end_date), '') IS NULL
            OR STR_TO_DATE(s.end_date, '%Y-%m-%d') >=
               DATE_ADD(c.cohort_month, INTERVAL 4 MONTH)
        )
        AND STR_TO_DATE(s.start_date, '%Y-%m-%d')
            >= DATE_ADD(c.cohort_month, INTERVAL 3 MONTH)
        THEN 1 ELSE 0 END) AS m3_retained,
        MAX(CASE WHEN STR_TO_DATE(s.start_date, '%Y-%m-%d')
            < DATE_ADD(c.cohort_month, INTERVAL 7 MONTH)
        AND (
            NULLIF(TRIM(s.end_date), '') IS NULL
            OR STR_TO_DATE(s.end_date, '%Y-%m-%d') >=
               DATE_ADD(c.cohort_month, INTERVAL 7 MONTH)
        )
        AND STR_TO_DATE(s.start_date, '%Y-%m-%d')
            >= DATE_ADD(c.cohort_month, INTERVAL 6 MONTH)
        THEN 1 ELSE 0 END) AS m6_retained,
        MAX(CASE WHEN STR_TO_DATE(s.start_date, '%Y-%m-%d')
            < DATE_ADD(c.cohort_month, INTERVAL 13 MONTH)
        AND (
            NULLIF(TRIM(s.end_date), '') IS NULL
            OR STR_TO_DATE(s.end_date, '%Y-%m-%d') >=
               DATE_ADD(c.cohort_month, INTERVAL 13 MONTH)
        )
        AND STR_TO_DATE(s.start_date, '%Y-%m-%d')
            >= DATE_ADD(c.cohort_month, INTERVAL 12 MONTH)
        THEN 1 ELSE 0 END) AS m12_retained
    FROM user_cohorts c
    LEFT JOIN subscriptions_clean s
        ON c.user_id = s.user_id
    GROUP BY c.user_id, c.cohort_month
)
SELECT
    DATE_FORMAT(cohort_month, '%Y-%m') AS signup_cohort,
    COUNT(*) AS cohort_size,
    ROUND(100.0 * SUM(m1_retained) / COUNT(*), 2) AS month_1_pct,
    ROUND(100.0 * SUM(m3_retained) / COUNT(*), 2) AS month_3_pct,
    ROUND(100.0 * SUM(m6_retained) / COUNT(*), 2) AS month_6_pct,
    ROUND(100.0 * SUM(m12_retained) / COUNT(*), 2) AS month_12_pct
FROM retention
GROUP BY cohort_month
ORDER BY cohort_month;

-- Q13. How does Month-3 retention differ by acquisition channel, plan, company size, and billing cycle?
WITH cohort_users AS (
    SELECT
        u.user_id,
        u.acquisition_channel,
        u.company_size,
        u.plan_at_signup,
        STR_TO_DATE(
            DATE_FORMAT(
                STR_TO_DATE(u.signup_date, '%Y-%m-%d'),
                '%Y-%m-01'
            ),
            '%Y-%m-%d'
        ) AS cohort_month
    FROM eligible_users u
    WHERE STR_TO_DATE(u.signup_date, '%Y-%m-%d') IS NOT NULL
      AND LOWER(COALESCE(u.is_internal_test, 'false'))
          NOT IN ('1', 'true', 'yes')
),
user_retention AS (
    SELECT
        c.*,
        COALESCE(s.billing_cycle, 'Unknown') AS billing_cycle,
        MAX(
            CASE
                WHEN STR_TO_DATE(s.start_date, '%Y-%m-%d')
                     < DATE_ADD(c.cohort_month, INTERVAL 4 MONTH)
                 AND STR_TO_DATE(s.start_date, '%Y-%m-%d')
                     >= DATE_ADD(c.cohort_month, INTERVAL 3 MONTH)
                 AND (
                     NULLIF(TRIM(s.end_date), '') IS NULL
                     OR STR_TO_DATE(s.end_date, '%Y-%m-%d')
                        >= DATE_ADD(c.cohort_month, INTERVAL 4 MONTH)
                 )
                THEN 1 ELSE 0
            END
        ) AS retained_m3
    FROM cohort_users c
    LEFT JOIN subscriptions_clean s
        ON c.user_id = s.user_id
    GROUP BY
        c.user_id, c.acquisition_channel, c.company_size,
        c.plan_at_signup, c.cohort_month, s.billing_cycle
)
SELECT
    acquisition_channel,
    plan_at_signup,
    company_size,
    billing_cycle,
    COUNT(DISTINCT user_id) AS users,
    ROUND(100.0 * AVG(retained_m3), 2) AS month_3_retention_pct
FROM user_retention
GROUP BY
    acquisition_channel, plan_at_signup,
    company_size, billing_cycle
ORDER BY month_3_retention_pct DESC;

-- CASE
                WHEN STR_TO_DATE(s.start_date, '%Y-%m-%d')
                     < DATE_ADD(c.cohort_month, INTERVAL 4 MONTH)
                 AND STR_TO_DATE(s.start_date, '%Y-%m-%d')
                     >= DATE_ADD(c.cohort_month, INTERVAL 3 MONTH)
                 AND (
                     NULLIF(TRIM(s.end_date), '') IS NULL
                     OR STR_TO_DATE(s.end_date, '%Y-%m-%d')
                        >= DATE_ADD(c.cohort_month, INTERVAL 4 MONTH)
                 )
                THEN 1 ELSE 0
            END
        ) AS retained_m3
    FROM cohort_users c
    LEFT JOIN subscriptions_clean s
        ON c.user_id = s.user_id
    GROUP BY
        c.user_id, c.acquisition_channel, c.company_size,
        c.plan_at_signup, c.cohort_month, s.billing_cycle
)
SELECT
    acquisition_channel,
    plan_at_signup,
    company_size,
    billing_cycle,
    COUNT(DISTINCT user_id) AS users,
    ROUND(100.0 * AVG(retained_m3), 2) AS month_3_retention_pct
FROM user_retention
GROUP BY
    acquisition_channel, plan_at_signup,
    company_size, billing_cycle
ORDER BY month_3_retention_pct DESC;


-- Q14. Which signup cohort has the best and worst Month-3 retention?

WITH cohort_users AS (
    SELECT
        user_id,
        STR_TO_DATE(
            DATE_FORMAT(
                STR_TO_DATE(signup_date, '%Y-%m-%d'),
                '%Y-%m-01'
            ),
            '%Y-%m-%d'
        ) AS cohort_month
    FROM eligible_users
    WHERE STR_TO_DATE(signup_date, '%Y-%m-%d') IS NOT NULL
      AND LOWER(COALESCE(is_internal_test, 'false'))
          NOT IN ('1', 'true', 'yes')
),
cohort_retention AS (
    SELECT
        c.cohort_month,
        c.user_id,
        MAX(
            CASE
                WHEN STR_TO_DATE(s.start_date, '%Y-%m-%d')
                     >= DATE_ADD(c.cohort_month, INTERVAL 3 MONTH)
                 AND STR_TO_DATE(s.start_date, '%Y-%m-%d')
                     < DATE_ADD(c.cohort_month, INTERVAL 4 MONTH)
                 AND (
                     NULLIF(TRIM(s.end_date), '') IS NULL
                     OR STR_TO_DATE(s.end_date, '%Y-%m-%d')
                        >= DATE_ADD(c.cohort_month, INTERVAL 4 MONTH)
                 )
                THEN 1 ELSE 0
            END
        ) AS retained_m3
    FROM cohort_users c
    LEFT JOIN subscriptions_clean s ON c.user_id = s.user_id
    GROUP BY c.cohort_month, c.user_id
)
SELECT
    DATE_FORMAT(cohort_month, '%Y-%m') AS cohort,
    COUNT(*) AS cohort_size,
    ROUND(100.0 * AVG(retained_m3), 2) AS month_3_retention_pct,
    RANK() OVER (ORDER BY AVG(retained_m3) DESC) AS best_rank,
    RANK() OVER (ORDER BY AVG(retained_m3) ASC) AS worst_rank
FROM cohort_retention
GROUP BY cohort_month
HAVING COUNT(*) >= 10
ORDER BY month_3_retention_pct DESC;

-- Q15. How are monthly signup counts changing over time?
WITH monthly AS (
    SELECT
        STR_TO_DATE(
            CONCAT(signup_month, '-01'),
            '%Y-%m-%d'
        ) AS month_date,
        signups
    FROM monthly_signups
)
SELECT
    DATE_FORMAT(month_date, '%Y-%m') AS signup_month,
    signups,
    LAG(signups) OVER (ORDER BY month_date) AS previous_month_signups,
    signups - LAG(signups) OVER (ORDER BY month_date) AS signup_change,
    ROUND(
        100.0 * (
            signups - LAG(signups) OVER (ORDER BY month_date)
        ) / NULLIF(
            LAG(signups) OVER (ORDER BY month_date), 0
        ),
        2
    ) AS mom_growth_pct
FROM monthly
ORDER BY month_date;

-- Section 4 — Churn and engagement analytics
-- Q16. What are the monthly customer churn and revenue churn rates?

WITH ended_subscriptions AS (
    SELECT
        DATE_FORMAT(
            STR_TO_DATE(end_date, '%Y-%m-%d'),
            '%Y-%m-01'
        ) AS churn_month,
        COUNT(DISTINCT user_id) AS churned_customers,
        SUM(
            CAST(NULLIF(TRIM(mrr), '') AS DECIMAL(18,2))
        ) AS churned_mrr
    FROM subscriptions_clean
    WHERE STR_TO_DATE(end_date, '%Y-%m-%d') IS NOT NULL
    GROUP BY DATE_FORMAT(
        STR_TO_DATE(end_date, '%Y-%m-%d'), '%Y-%m-01'
    )
),
monthly AS (
    SELECT
        STR_TO_DATE(
            CONCAT(snapshot_month, '-01'),
            '%Y-%m-%d'
        ) AS month_date,
        paying_customers,
        CAST(observed_mrr AS DECIMAL(18,2)) AS mrr
    FROM monthly_subscription_metrics
)
SELECT
    e.churn_month,
    e.churned_customers,
    prev.paying_customers AS previous_paying_customers,
    ROUND(
        100.0 * e.churned_customers /
        NULLIF(prev.paying_customers, 0),
        2
    ) AS logo_churn_pct,
    ROUND(e.churned_mrr, 2) AS ended_subscription_mrr,
    ROUND(
        100.0 * e.churned_mrr / NULLIF(prev.mrr, 0),
        2
    ) AS approximate_revenue_churn_pct
FROM ended_subscriptions e
LEFT JOIN monthly prev
    ON prev.month_date = DATE_SUB(
        STR_TO_DATE(e.churn_month, '%Y-%m-%d'),
        INTERVAL 1 MONTH
    )
ORDER BY e.churn_month;

-- Q17. Which subscription-tenure bucket has the most churn?
WITH subscription_tenure AS (
    SELECT
        user_id,
        subscription_id,
        STR_TO_DATE(start_date, '%Y-%m-%d') AS start_dt,
        STR_TO_DATE(end_date, '%Y-%m-%d') AS end_dt,
        CASE
            WHEN STR_TO_DATE(end_date, '%Y-%m-%d') IS NULL
                THEN 'Not ended / unknown'
            WHEN TIMESTAMPDIFF(
                MONTH,
                STR_TO_DATE(start_date, '%Y-%m-%d'),
                STR_TO_DATE(end_date, '%Y-%m-%d')
            ) <= 3 THEN '0-3 months'
            WHEN TIMESTAMPDIFF(
                MONTH,
                STR_TO_DATE(start_date, '%Y-%m-%d'),
                STR_TO_DATE(end_date, '%Y-%m-%d')
            ) <= 6 THEN '4-6 months'
            WHEN TIMESTAMPDIFF(
                MONTH,
                STR_TO_DATE(start_date, '%Y-%m-%d'),
                STR_TO_DATE(end_date, '%Y-%m-%d')
            ) <= 12 THEN '7-12 months'
            ELSE '12+ months'
        END AS tenure_bucket
    FROM subscriptions_clean
)
SELECT
    tenure_bucket,
    COUNT(*) AS subscription_periods,
    COUNT(DISTINCT user_id) AS customers
FROM subscription_tenure
GROUP BY tenure_bucket
ORDER BY FIELD(
    tenure_bucket,
    '0-3 months',
    '4-6 months',
    '7-12 months',
    '12+ months',
    'Not ended / unknown'
);

-- Q18. What percentage of churn appears to be involuntary because of failed payments?

WITH failed_users AS (
    SELECT DISTINCT user_id
    FROM payments_clean
    WHERE LOWER(COALESCE(payment_status, '')) LIKE '%fail%'
),
ended_users AS (
    SELECT DISTINCT user_id
    FROM subscriptions_clean
    WHERE STR_TO_DATE(end_date, '%Y-%m-%d') IS NOT NULL
)
SELECT
    COUNT(*) AS ended_customers,
    SUM(CASE WHEN f.user_id IS NOT NULL THEN 1 ELSE 0 END)
        AS ended_customers_with_failed_payment,
    ROUND(
        100.0 * SUM(
            CASE WHEN f.user_id IS NOT NULL THEN 1 ELSE 0 END
        ) / NULLIF(COUNT(*), 0),
        2
    ) AS failed_payment_association_pct
FROM ended_users e
LEFT JOIN failed_users f ON e.user_id = f.user_id;

-- Q19. Which active customers have not been active in the last 30 days?

SELECT
    ca.user_id,
    ca.country,
    ca.acquisition_channel,
    ca.company_size,
    ca.last_activity,
    ca.days_since_last_activity,
    ca.engagement_segment
FROM customer_analysis ca
WHERE EXISTS (
    SELECT 1
    FROM subscriptions_clean s
    WHERE s.user_id = ca.user_id
      AND LOWER(COALESCE(s.status, '')) = 'active'
)
AND (
    ca.last_activity IS NULL
    OR TRIM(ca.last_activity) = ''
    OR STR_TO_DATE(ca.last_activity, '%Y-%m-%d %H:%i:%s')
       < DATE_SUB(CURDATE(), INTERVAL 30 DAY)
)
ORDER BY
    STR_TO_DATE(ca.last_activity, '%Y-%m-%d %H:%i:%s');
    
    -- Q20. Do customers who invite teammates have lower churn?
    
    WITH user_invites AS (
    SELECT
        u.user_id,
        MAX(
            CASE
                WHEN LOWER(COALESCE(e.event_name, '')) LIKE '%invite%'
                THEN 1 ELSE 0
            END
        ) AS invited_teammate
    FROM eligible_users u
    LEFT JOIN events_clean e ON u.user_id = e.user_id
    GROUP BY u.user_id
),
user_churn AS (
    SELECT
        user_id,
        MAX(
            CASE
                WHEN STR_TO_DATE(end_date, '%Y-%m-%d') IS NOT NULL
                 AND LOWER(COALESCE(status, '')) NOT IN
                     ('active', 'trialing')
                THEN 1 ELSE 0
            END
        ) AS churned
    FROM subscriptions_clean
    GROUP BY user_id
)
SELECT
    CASE WHEN i.invited_teammate = 1
         THEN 'Invited teammate'
         ELSE 'No invitation event'
    END AS invitation_group,
    COUNT(*) AS customers,
    SUM(COALESCE(c.churned, 0)) AS churned_customers,
    ROUND(
        100.0 * SUM(COALESCE(c.churned, 0)) / NULLIF(COUNT(*), 0),
        2
    ) AS churn_pct
FROM user_invites i
LEFT JOIN user_churn c ON i.user_id = c.user_id
GROUP BY invitation_group;

-- Section 5 — LTV, CAC, and revenue quality
-- Q21. What is the realised customer payment value by acquisition channel and signup cohort?
WITH payment_totals AS (
    SELECT
        user_id,
        SUM(
            CASE
                WHEN LOWER(COALESCE(payment_status, '')) LIKE '%refund%'
                THEN -ABS(
                    CAST(NULLIF(TRIM(amount), '') AS DECIMAL(18,2))
                )
                WHEN LOWER(COALESCE(payment_status, ''))
                     IN ('success', 'successful', 'succeeded', 'paid')
                THEN CAST(
                    NULLIF(TRIM(amount), '') AS DECIMAL(18,2)
                )
                ELSE 0
            END
        ) AS realised_payment_value
    FROM payments_clean
    GROUP BY user_id
)
SELECT
    u.acquisition_channel,
    DATE_FORMAT(
        STR_TO_DATE(u.signup_date, '%Y-%m-%d'),
        '%Y-%m'
    ) AS signup_cohort,
    COUNT(DISTINCT u.user_id) AS customers,
    ROUND(SUM(COALESCE(p.realised_payment_value, 0)), 2)
        AS realised_payment_value,
    ROUND(
        SUM(COALESCE(p.realised_payment_value, 0)) /
        NULLIF(COUNT(DISTINCT u.user_id), 0),
        2
    ) AS average_realised_value_per_customer
FROM eligible_users u
LEFT JOIN payment_totals p ON u.user_id = p.user_id
WHERE LOWER(COALESCE(u.is_internal_test, 'false'))
      NOT IN ('1', 'true', 'yes')
GROUP BY u.acquisition_channel, signup_cohort
ORDER BY signup_cohort, realised_payment_value DESC;

-- Q22. What are CAC, LTV:CAC ratio, and payback period by acquisition channel and month?
WITH monthly_acquisitions AS (
    SELECT
        DATE_FORMAT(
            STR_TO_DATE(u.signup_date, '%Y-%m-%d'),
            '%Y-%m'
        ) AS signup_month,
        u.acquisition_channel AS channel,
        COUNT(DISTINCT u.user_id) AS acquired_customers
    FROM eligible_users u
    WHERE STR_TO_DATE(u.signup_date, '%Y-%m-%d') IS NOT NULL
      AND LOWER(COALESCE(u.is_internal_test, 'false'))
          NOT IN ('1', 'true', 'yes')
    GROUP BY signup_month, channel
),
spend AS (
    SELECT
        COALESCE(
            NULLIF(TRIM(marketing_month), ''),
            DATE_FORMAT(
                STR_TO_DATE(month, '%Y-%m-%d'),
                '%Y-%m'
            )
        ) AS spend_month,
        channel,
        SUM(
            CAST(NULLIF(TRIM(spend), '') AS DECIMAL(18,2))
        ) AS total_spend
    FROM marketing_spend_clean
    GROUP BY spend_month, channel
)
SELECT
    a.signup_month,
    a.channel,
    a.acquired_customers,
    ROUND(s.total_spend, 2) AS marketing_spend,
    ROUND(
        s.total_spend / NULLIF(a.acquired_customers, 0),
        2
    ) AS cac
FROM monthly_acquisitions a
LEFT JOIN spend s
    ON a.signup_month = s.spend_month
   AND a.channel = s.channel
ORDER BY a.signup_month, a.channel;

-- Q23. What are the monthly failed-payment and refund rates?
WITH payment_flags AS (
    SELECT
        DATE_FORMAT(
            STR_TO_DATE(payment_date, '%Y-%m-%d'),
            '%Y-%m'
        ) AS payment_month,
        payment_status,
        amount,
        CASE
            WHEN LOWER(COALESCE(payment_status, '')) LIKE '%fail%'
            THEN 1 ELSE 0
        END AS is_failed,
        CASE
            WHEN LOWER(COALESCE(payment_status, '')) LIKE '%refund%'
            THEN 1 ELSE 0
        END AS is_refund
    FROM payments_clean
    WHERE STR_TO_DATE(payment_date, '%Y-%m-%d') IS NOT NULL
)
SELECT
    payment_month,
    COUNT(*) AS total_payment_records,
    SUM(is_failed) AS failed_payment_records,
    ROUND(100.0 * AVG(is_failed), 2) AS failed_payment_rate_pct,
    SUM(is_refund) AS refund_records,
    ROUND(100.0 * AVG(is_refund), 2) AS refund_record_rate_pct,
    ROUND(
        SUM(
            CASE WHEN is_refund = 1
                 THEN CAST(NULLIF(TRIM(amount), '') AS DECIMAL(18,2))
                 ELSE 0 END
        ),
        2
    ) AS refund_record_amount
FROM payment_flags
GROUP BY payment_month
ORDER BY payment_month;

-- Q24. Do customers who received a first-month discount have worse retention?
SELECT
    TABLE_NAME,
    COLUMN_NAME,
    DATA_TYPE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_SCHEMA = DATABASE()
  AND TABLE_NAME IN (
      'payments_clean',
      'subscriptions_clean',
      'eligible_users',
      'events_clean'
  )
ORDER BY TABLE_NAME, ORDINAL_POSITION;

SELECT
    payment_status,
    COUNT(*) AS total_records,
    SUM(
        CAST(NULLIF(TRIM(amount), '') AS DECIMAL(18,2))
    ) AS total_amount
FROM payments_clean
GROUP BY payment_status
ORDER BY total_records DESC;


-- Q25. Which customers have payments but no active subscription, or an active subscription but no successful payment?
WITH payment_summary AS (
    SELECT
        user_id,
        COUNT(*) AS payment_records,
        SUM(
            CASE
                WHEN LOWER(COALESCE(payment_status, ''))
                     IN ('success', 'successful', 'succeeded', 'paid')
                THEN 1 ELSE 0
            END
        ) AS successful_payments
    FROM payments_clean
    GROUP BY user_id
),
subscription_summary AS (
    SELECT
        user_id,
        MAX(
            CASE
                WHEN LOWER(COALESCE(status, '')) = 'active'
                THEN 1 ELSE 0
            END
        ) AS has_active_subscription
    FROM subscriptions_clean
    GROUP BY user_id
),
all_users AS (
    SELECT user_id FROM payments_clean
    UNION
    SELECT user_id FROM subscriptions_clean
)
SELECT
    u.user_id,
    COALESCE(p.payment_records, 0) AS payment_records,
    COALESCE(p.successful_payments, 0) AS successful_payments,
    COALESCE(s.has_active_subscription, 0) AS has_active_subscription,
    CASE
        WHEN COALESCE(p.successful_payments, 0) > 0
         AND COALESCE(s.has_active_subscription, 0) = 0
            THEN 'Payment but no active subscription'
        WHEN COALESCE(p.successful_payments, 0) = 0
         AND COALESCE(s.has_active_subscription, 0) = 1
            THEN 'Active subscription but no successful payment'
        WHEN COALESCE(p.successful_payments, 0) = 0
         AND COALESCE(s.has_active_subscription, 0) = 0
            THEN 'Neither active subscription nor successful payment'
        ELSE 'Payment and active subscription'
    END AS integrity_status
FROM all_users u
LEFT JOIN payment_summary p ON u.user_id = p.user_id
LEFT JOIN subscription_summary s ON u.user_id = s.user_id
WHERE
    (
        COALESCE(p.successful_payments, 0) > 0
        AND COALESCE(s.has_active_subscription, 0) = 0
    )
    OR
    (
        COALESCE(p.successful_payments, 0) = 0
        AND COALESCE(s.has_active_subscription, 0) = 1
    )
ORDER BY integrity_status, u.user_id;

DESCRIBE cohort_retention;




