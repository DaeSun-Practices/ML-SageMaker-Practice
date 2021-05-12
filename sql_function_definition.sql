DELIMITER $$
CREATE DEFINER = `admin` @ `%` FUNCTION `churn` (
    state varchar(2048), acc_length bigint(20),
    area_code(20), int_plan varchar(2048),
    vmail_plan varchar(2048), vmail_msg bigint(20),
    day_mins double, day_calls bigint(20),
    night_mins double, night_calls bigint(20),
    int_mins double, int_calls bigint(20),
    cust_service_calls bigint(20)) RETURNS varchar(2048) CHARSET latin1
alias aws_sagemaker_invoke_endpoint
    endpoint name 'sqlai-scikit-endpoint' $$
DELIMITER;