from kivy.app import App
from kivy.uix.boxlayout import BoxLayout
from kivy.uix.button import Button
from kivy.core.window import Window

Window.size = (300, 200)


class MainWindow(BoxLayout):
    def __init__(self):
        super().__init__()
        
        self.button = Button(text="Hello, World?")
        self.button.size_hint = (0.3, 0.3)
        self.button.pos_hint = {"center_x": 0.5, "center_y": 0.5}
        self.button.bind(on_press=self.handle_button_clicked)

        self.add_widget(self.button)

    def handle_button_clicked(self, event):
        self.button.text = "Hello, World!"


class MyApp(App):
    def build(self):
        self.title = "Hello, World!"
        self.options = {"width": 300, "height": 500}
        return MainWindow()


app = MyApp()
app.run()
