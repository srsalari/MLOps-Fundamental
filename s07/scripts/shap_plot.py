"""Optional: SHAP summary plot of the @champion model, logged as an artifact of its run.

Optional Session 7 script that shows "explainability": which features have the biggest
effect on the model's prediction? For every row and every feature, SHAP gives one number
that says how much that feature pushed the churn probability up or down. The beeswarm
plot shows all these numbers in one picture.

Run (from the project root, after `@champion` exists):

    uv run --with shap==0.54.1 python scripts/shap_plot.py

Input: the `@champion` model from the Registry and `data/processed/test.csv`.
Output: the file `shap_summary.png` in the current folder. The same file is also uploaded
as an artifact to the run that trained the champion model (in the MLflow UI, Artifacts tab).
"""

import matplotlib

# "Agg" = draw into files only, never open a window. Must be set BEFORE importing pyplot,
# which is why the imports below carry "noqa: E402" (ruff: import not at top of file).
matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402
import mlflow  # noqa: E402
import pandas as pd  # noqa: E402
import shap  # noqa: E402

from churn.preprocess import OUT_DIR, TARGET  # noqa: E402
from churn.registry import CHAMPION, MODEL_NAME, check_download_setting, connect  # noqa: E402

check_download_setting()  # avoid the load_model hang (see churn/registry.py)
client = connect()
mv = client.get_model_version_by_alias(MODEL_NAME, CHAMPION)
model = mlflow.sklearn.load_model(f"models:/{MODEL_NAME}@{CHAMPION}")

X = pd.read_csv(OUT_DIR / "test.csv").drop(columns=[TARGET])
# The model is a Pipeline with two named steps: "pre" (ColumnTransformer) and "clf"
# (LogisticRegression). SHAP needs the numeric matrix and the classifier separately.
pre, clf = model.named_steps["pre"], model.named_steps["clf"]
Xt = pre.transform(X)  # raw columns -> numbers (scaled + one-hot), exactly what clf saw
names = pre.get_feature_names_out()  # readable names such as "num__tenure_months"
# LinearExplainer is the exact and fast SHAP method for linear models like LogisticRegression.
explainer = shap.LinearExplainer(clf, Xt)
values = explainer(Xt)  # one SHAP value per row and per feature
values.feature_names = list(names)  # so the plot shows names instead of "Feature 0..N"

# show=False: do not display, we save it ourselves. max_display=12: only the top 12 features.
shap.plots.beeswarm(values, show=False, max_display=12)
plt.tight_layout()  # avoid cut-off labels
plt.savefig("shap_summary.png", dpi=120)
# Attach the picture to the run that trained the champion model (it shows up in the MLflow UI).
client.log_artifact(mv.run_id, "shap_summary.png")
print(f"shap_summary.png logged to run {mv.run_id[:8]} (version {mv.version}, @{CHAMPION})")
