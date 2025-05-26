document.addEventListener("DOMContentLoaded", function () {
  const form = document.getElementById("quizForm");
  if (form) {
    form.addEventListener("submit", function (e) {
      e.preventDefault();
      const answer = form.q1.value;
      const result = document.getElementById("result");
      if (answer === "a") {
        result.textContent = "Correct!";
      } else {
        result.textContent = "Incorrect. Review slope rules.";
      }
    });
  }
});